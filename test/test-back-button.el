;;; test-back-button.el --- Tests for back-button -*- lexical-binding: t; -*-

;; Copyright (C) 2021 The Authors of back-button.el

;; Authors: dickmao <github id: dickmao>
;; URL: https://github.com/dickmao/back-button

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

;; Test stuff.

;;; Code:

(require 'back-button)

(ert-deftest test-back-button ()
  (let ((ring (back-button--ring-of (selected-frame))))
    (pop-to-buffer "foo")
    (back-button--push-wconf (selected-frame))
    (should (= 1 (back-button--ring-ipush ring)))
    (should (equal (back-button-forward) "At newest mark"))
    (should (= 2 (length (window-list (selected-frame) 'ex-minibuffer))))
    (delete-other-windows)
    (should (= 1 (length (window-list (selected-frame) 'ex-minibuffer))))
    (back-button--push-wconf (selected-frame))
    (should (= 2 (back-button--ring-ipush ring)))
    (should (= 1 (back-button--ring-iscan ring)))
    (should (= 1 (length (cdr (back-button--wconf-key
			       (back-button--ring-last-push ring))))))
    (should (equal (back-button--wconf-key (back-button--ring-top ring))
		   (back-button--wconf-key (back-button-back))))
    (tab-bar-new-tab)
    (tab-bar-rename-tab "baz")
    (let ((ring-baz (back-button--ring-of (selected-frame))))
      (should (= 0 (back-button--ring-ipush ring-baz)))
      (should-not (back-button--ring-iscan ring-baz))
      (back-button--push-wconf (selected-frame))
      (should (= 1 (back-button--ring-ipush ring-baz)))
      (should (equal (back-button-forward) "At newest mark")))
    (should (cl-some (lambda (pair) (> (cdar pair) 0)) back-button--ring-by-tab))
    (tab-bar-close-tab 0)
    (should-not (cl-some (lambda (pair) (> (cdar pair) 0)) back-button--ring-by-tab))))

(provide 'test-back-button)

;;; test-back-button.el ends here
