;; Copyright (C) 2016-2018  Vibhav Pant <vibhavp@gmail.com>  -*- lexical-binding: t -*-

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Code:

(require 'compile)
(require 'url-util)
(require 'url-parse)
(require 'subr-x)

(defconst lsp--message-type-face
  `((1 . ,compilation-error-face)
    (2 . ,compilation-warning-face)
    (3 . ,compilation-message-face)
    (4 . ,compilation-info-face)))

(defcustom lsp-print-io nil
  "If non-nil, print all messages to and from the language server to *Messages*."
  :group 'lsp-mode
  :type 'boolean)

(defvar lsp--uri-file-prefix (pcase system-type
                               (`windows-nt "file:///")
                               (_ "file://"))
  "Prefix for a file-uri.")

(defvar-local lsp-buffer-uri nil
  "If set, return it instead of calculating it using `buffer-file-name'.")

(define-error 'lsp-error "Unknown lsp-mode error")
(define-error 'lsp-empty-response-error
  "Empty response from the language server" 'lsp-error)
(define-error 'lsp-timed-out-error
  "Timed out while waiting for a response from the language server" 'lsp-error)
(define-error 'lsp-capability-not-supported
  "Capability not supported by the language server" 'lsp-error)

(defun lsp--propertize (str type)
  "Propertize STR as per TYPE."
  (propertize str 'face (alist-get type lsp--message-type-face)))

(defvar lsp--no-response)

;; from http://emacs.stackexchange.com/questions/8082/how-to-get-buffer-position-given-line-number-and-column-number
(defun lsp--position-to-point (params)
  "Convert Position object in PARAMS to a point."
  (save-excursion
    (save-restriction
      (widen)
      (goto-char (point-min))
      (forward-line (gethash "line" params))
      (forward-char (gethash "character" params))
      (point))))

;;; TODO: Use the current LSP client name instead of lsp-mode for the type.
(defun lsp-warn (message &rest args)
  "Display a warning message made from (`format-message' MESSAGE ARGS...).
This is equivalent to `display-warning', using `lsp-mode' as the type and
`:warning' as the level."
  (display-warning 'lsp-mode (apply #'format-message message args)))

(defun lsp-make-traverser (name)
  "Return a closure that walks up the current directory until NAME is found.
NAME can either be a string or a predicate used for `locate-dominating-file'.
The value returned by the function will be the directory name for NAME.

If no such directory could be found, log a warning and return `default-directory'"
  (lambda ()
    (let ((dir (locate-dominating-file "." name)))
      (if dir
        (file-truename dir)
        (lsp-warn
          "Couldn't find project root, using the current directory as the root.")
        default-directory))))

(defun lsp--get-uri-handler (scheme)
  "Get uri handler for SCHEME in the current workspace."
  (when lsp--cur-workspace
    (gethash scheme (lsp--client-uri-handlers
                      (lsp--workspace-client lsp--cur-workspace)))))

(defun lsp--uri-to-path (uri)
  "Convert URI to a file path."
  (let* ((url (url-generic-parse-url (url-unhex-string uri)))
         (type (url-type url))
         (file (url-filename url)))
    (if (and type (not (string= type "file")))
      (let ((handler (lsp--get-uri-handler type)))
        (if handler
          (funcall handler uri)
          (error "Unsupported file scheme: %s" uri)))
      ;; `url-generic-parse-url' is buggy on windows:
      ;; https://github.com/emacs-lsp/lsp-mode/pull/265
      (or (and (eq system-type 'windows-nt)
            (eq (elt file 0) ?\/)
            (substring file 1))
        file))))

(define-inline lsp--buffer-uri ()
  "Return URI of the current buffer."
  (inline-quote
    (or lsp-buffer-uri (lsp--path-to-uri buffer-file-name))))

(define-inline lsp--path-to-uri (path)
  "Convert PATH to a uri."
  (inline-quote
    (concat lsp--uri-file-prefix
      (url-hexify-string (file-truename ,path) url-path-allowed-chars))))

(provide 'lsp-common)
;;; lsp-common.el ends here
