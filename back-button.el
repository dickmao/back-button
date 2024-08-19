;;; back-button.el --- go back dammit -*- lexical-binding: t; coding: utf-8 -*-

;; Copyright (C) 2024 The Authors

;; Authors: dickmao <github id: dickmao>
;; Version: 0.1.0
;; Keywords: maint tools
;; URL: https://commandlinesystems.com
;; Package-Requires: ((emacs "27.1"))

;; This file is NOT part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with back-button.el.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; ``(require 'back-button)``
;;
;; ``C-,`` Backward
;;
;; ``C-.`` Forward

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defcustom back-button-size 256
  "How far to go back."
  :group 'back-button
  :type 'integer)

(cl-defstruct (back-button--wconf)
  "The KEY ensures consecutive WCONF is sufficiently distinct.
Since WCONF is opaque, we must keep an auxiliary KEY of the form
(POINT-MARKER ([WBUF1 ORIG1] [WBUF2 ORIG2] ...)).  We don't use
window-configuration-equal-p since among other things it compares
minibuffers, and current-window-configuration doesn't include
point-marker (well, wtf not?)."
  key wconf)

(cl-defstruct (back-button--ring
	       (:constructor nil)
               (:constructor back-button--ring-make
			     (&aux (ipush 0)
				   (iscan nil)
				   (length back-button-size)
				   (vec (make-vector back-button-size nil)))))
  ipush iscan length vec)

(defvar back-button--ring-by-tab nil)

(defun back-button--valid-wconf (wconf)
  (cl-destructuring-bind (marker . buffer-origins)
      (back-button--wconf-key wconf)
    (and (cl-every #'buffer-live-p
		   (mapcar (lambda (arr) (aref arr 0))
			   buffer-origins))
	 (eq (marker-buffer marker) (aref (car buffer-origins) 0))
	 (with-current-buffer (marker-buffer marker)
	   (and (<= (point-min) (marker-position marker))
		(<= (marker-position marker) (point-max)))))))

(defun back-button--doit (wconf)
  (when (and (not (equal (back-button--wconf-key wconf)
			 (back-button--key-of (selected-frame))))
	     (back-button--valid-wconf wconf))
    (prog1 t
      (cl-macrolet ((compatible-set-wconf
		      (conf)
		      (if (special-variable-p 'window-restore-killed-buffer-windows)
			  `(let (window-restore-killed-buffer-windows)
			     (set-window-configuration ,conf nil 'ex-minibuffer))
			`(set-window-configuration ,conf))))
	(compatible-set-wconf (back-button--wconf-wconf wconf)))
      (goto-char (car (back-button--wconf-key wconf))))))

(defun back-button--ring-of (frame &optional tab)
  (if-let ((tab-index (if tab
			  (tab-bar--tab-index tab nil frame)
			(tab-bar--current-tab-index nil frame)))
	   (extant (assoc-default (cons frame tab-index)
				  back-button--ring-by-tab)))
      extant
    (let ((new (back-button--ring-make)))
      (prog1 new
	(push (cons (cons frame tab-index) new) back-button--ring-by-tab)))))

(defmacro back-button--suspend (&rest body)
  "Constantly de/activating protects against re-evals
that would unadvice push-mark."
  `(unwind-protect
       (progn (funcall (symbol-function 'back-button--deactivate))
	      ,@body)
     (funcall (symbol-function 'back-button--activate))))

(defvar back-button-mode-map)

(defun back-button--scan-hook ()
  (when (and (not (eq this-command 'back-button-back))
	     (not (eq this-command 'back-button-forward)))
    (mapc (lambda (ring)
	    (setf (back-button--ring-iscan ring) nil))
	  (delq nil (mapcar #'back-button--ring-of (frame-list))))
    (remove-hook 'post-command-hook #'back-button--scan-hook)
    (when (and (fboundp 'keymap-lookup)
	       (funcall (symbol-function 'keymap-lookup)
			back-button-mode-map
			(key-description (vector last-input-event))))
      (user-error "back-button-mode: %s was occluded by another keymap"
		  (key-description (vector last-input-event))))))

(defun back-button--move (direction callback)
  (back-button--suspend
   (add-hook 'post-command-hook #'back-button--scan-hook)
   (when-let ((ring (back-button--ring-of (selected-frame))))
     (setf (back-button--ring-iscan ring)
	   (or (back-button--ring-iscan ring) (back-button--ring-ipush ring)))
     (catch 'done
       (while t
	 (if-let ((wconf (funcall direction ring)))
	     (when (back-button--doit wconf)
	       (throw 'done (funcall callback ring wconf)))
	   (throw 'done nil)))))))

(defun back-button-back ()
  (interactive)
  (or (back-button--move #'back-button--ring-back #'back-button--ring-push)
      (message "At oldest mark")))

(defun back-button-forward ()
  (interactive)
  (or (back-button--move #'back-button--ring-forward (lambda (_ring wconf) wconf))
      (message "At newest mark")))

(cl-defmethod back-button--ring-push (ring wconf)
  (when wconf
    (aset (back-button--ring-vec ring)
	  (back-button--ring-ipush ring)
	  wconf)
    (setf (back-button--ring-ipush ring)
	  (back-button--ring-1+ ring (back-button--ring-ipush ring)))
    (back-button--ring-last-push ring)))

(cl-defmethod back-button--ring-back (ring)
  (when-let ((top (back-button--ring-top ring)))
    (prog1 top
      (setf (back-button--ring-iscan ring)
	    (back-button--ring-1- ring (back-button--ring-iscan ring))))))

(cl-defmethod back-button--ring-forward (ring)
  (when-let ((next (aref (back-button--ring-vec ring)
			 (back-button--ring-iscan ring))))
    (prog1 next
      (setf (back-button--ring-iscan ring)
	    (back-button--ring-1+ ring (back-button--ring-iscan ring))))))

(cl-defmethod back-button--ring-1+ (ring index)
  (mod (1+ index) (back-button--ring-length ring)))

(cl-defmethod back-button--ring-1- (ring index)
  (mod (1- index) (back-button--ring-length ring)))

(cl-defmethod back-button--ring-top (ring)
  (if (back-button--ring-iscan ring)
      (aref (back-button--ring-vec ring)
	    (back-button--ring-1- ring (back-button--ring-iscan ring)))
    (back-button--ring-last-push ring)))

(cl-defmethod back-button--ring-last-push (ring)
  (aref (back-button--ring-vec ring)
	(back-button--ring-1- ring (back-button--ring-ipush ring))))

(defun back-button--key-of (frame)
  (let ((buffer-origins (mapcar (lambda (w)
				  (apply #'vector
					 (window-buffer w)
					 (nbutlast (window-edges w) 2)))
				(window-list frame 'ex-minibuffer)))
	(mark (point-marker)))
    (when (member (marker-buffer mark)
		  (mapcar (lambda (arr) (aref arr 0)) buffer-origins))
      (cons mark buffer-origins))))

(defun back-button--push-wconf (window-or-frame)
  "Commit d7ac415, window.c line 4056."
  (when-let ((frame (when (eq window-or-frame (selected-frame))
		      window-or-frame))
	     (substantive-p (zerop (minibuffer-depth)))
	     (ring (back-button--ring-of frame)))
    (let ((key (back-button--key-of frame))
	  (prevailing-key
	   (when-let ((prevailing (back-button--ring-top ring)))
	     (back-button--wconf-key prevailing))))
      (when (and key (not (equal key prevailing-key)))
	(back-button--ring-push
	 ring
	 (make-back-button--wconf
	  :key key
	  :wconf (current-window-configuration frame)))))))

(let* ((advice (lambda (&rest _args)
		 (back-button--push-wconf (selected-frame))))
       (clean-tab (lambda (tab &rest _args)
		    (when-let ((found
				(catch 'found
				  (dolist (f (frame-list))
				    (when-let ((ix (tab-bar--tab-index tab nil f)))
				      (throw 'found (cons f ix)))))))
		      (setq back-button--ring-by-tab
			    (cl-remove-if
			     (lambda (pair)
			       (equal found (car pair)))
			     back-button--ring-by-tab))
		      ;; identifying tabs by ordinal is shit
		      ;; decrement all ordinals after deleted ix
		      (dolist (pair back-button--ring-by-tab)
			(cl-destructuring-bind ((f . i) . ring)
			    pair
			  (when (and (eq (car found) f)
				     (< (cdr found) i))
			    (setcdr (car pair) (1- i))))))))
       (clean-frame (lambda (frame &rest _args)
		      (setq back-button--ring-by-tab
			    (cl-remove-if
			     (lambda (pair)
			       (cl-destructuring-bind ((f . tab-index) . ring)
				   pair
				 (eq frame f)))
			     back-button--ring-by-tab))))
       (deactivate
	(lambda ()
	  (remove-function (symbol-function 'push-mark) advice)
	  (remove-function (symbol-function 'push-global-mark) advice)
	  (remove-hook 'window-state-change-functions #'back-button--push-wconf)
	  (remove-hook 'tab-bar-tab-pre-close-functions clean-tab)
	  (remove-hook 'delete-frame-functions clean-frame))))
  (defalias 'back-button--deactivate deactivate)
  (defalias 'back-button--activate
    (lambda ()
      (funcall deactivate)
      (add-function :after (symbol-function 'push-mark) advice)
      (add-function :after (symbol-function 'push-global-mark) advice)
      (add-hook 'window-state-change-functions #'back-button--push-wconf)
      (add-hook 'tab-bar-tab-pre-close-functions clean-tab)
      (add-hook 'delete-frame-functions clean-frame))))

(define-minor-mode back-button-mode
  "Superfluous minor mode for its higher-precedence keymap side effect."
  :global t
  :lighter nil
  :group 'back-button
  :keymap `((,(if (display-graphic-p) (kbd "C-,") (kbd "C-c ,")) . back-button-back)
	    (,(if (display-graphic-p) (kbd "C-.") (kbd "C-c .")) . back-button-forward))
  (funcall (symbol-function (if back-button-mode
				'back-button--activate
			      'back-button--deactivate))))

(back-button-mode)

(provide 'back-button)
;;; back-button.el ends here
