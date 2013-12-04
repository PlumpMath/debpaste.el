;;; debpaste.el --- emacs interface for <http://paste.debian.net/>

;; Copyright (C) 2013 Alex Kost

;; Author: Alex Kost <alezost@gmail.com>

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; For information about features provided by debian paste server,
;; read <http://paste.debian.net/rpc-interface.html>.

;;; Code:

(require 'cl-macs)
(require 'xml-rpc)

(defconst debpaste-server-url "http://paste.debian.net/server.pl"
  "URL of the XML-RPC paste server.")

(defgroup debpaste nil
  "Emacs interface for debian paste server."
  :group 'xml-rpc
  :group 'url)

(defun debpaste-send-command (cmd &rest opts)
  "Send command CMD with options OPTS to the paste server.
CMD is a symbol from `debpaste-commands'."
  (apply #'xml-rpc-method-call
         debpaste-server-url
         (debpaste-get-command-name cmd)
         opts))

(cl-defun debpaste-action (&key cmd opts filters)
  "Send command to the server and make some actions with output.

After sending command (method) CMD with option list OPTS, the
paste server returns some information which is transformed into
alist of parameters and values by `xml-rpc-method-call'.  This
alist (it is called \"info\" in this package) is passed as an
argument to the first function from the list FILTERS, the
returned result is passed to the second function from that list
and so on.

Each filter function should accept a single argument - info alist
and should return info alist.  Functions may add associations to
the alist.  In this case you might want to add descriptions of
the added symbols into `debpaste-param-description-alist'.

`debpaste-filter-intern' should be the first in the FILTERS list
as other functions from this package use symbols for working with
info parameters (see `debpaste-param-alist')."
  (let ((info (apply 'debpaste-send-command cmd opts)))
    (mapc (lambda (fun)
            (setq info (funcall fun info)))
          filters)))


;;; Server commands and returned parameters

(defvar debpaste-command-alist
  '((get-paste         . "paste.getPaste")
    (add-paste         . "paste.addPaste")
    (del-paste         . "paste.deletePaste")
    (get-langs         . "paste.getLanguages")
    (add-short-url     . "paste.addShortURL")
    (resolve-short-url . "paste.resolveShortURL")
    (short-url-clicks  . "paste.ShortURLClicks"))
  "Association list of symbols and names of server commands (methods).

Car of each assoc is a symbol used in code of this package;
cdr - is a command name (string) sent to the paste server.")

(defvar debpaste-param-alist
  '((ret          . "rc")
    (status       . "statusmessage")
    (text         . "code")
    (submitter    . "submitter")
    (id           . "id")
    (base-url     . "base_url")
    (view-url     . "view_url")
    (download-url . "download_url")
    (delete-url   . "delete_url")
    (digest       . "digest")
    (submit-date  . "submitdate")
    (expire-sec   . "expiredate"))
  "Association list of symbols and names of info parameters.

Car of each assoc is a symbol used in code of this package;
cdr - is a parameter name (string) returned by paste server.")

(defcustom debpaste-param-description-alist
  '((id           . "ID")
    (ret          . "Return code")
    (status       . "Server message")
    (base-url     . "Base URL")
    (view-url     . "View URL")
    (download-url . "Download URL")
    (delete-url   . "Delete URL")
    (digest       . "Digest (SHA1 value for deleting a paste)")
    (submitter    . "Submitter")
    (submit-date  . "Submitting date")
    (expire-date  . "Expiration date")
    (expire-sec   . "Expiration time (seconds)"))
  "Association list of symbols and descriptions of parameters.

Descriptions are used for displaying paste information.

Symbols are either from `debpaste-param-name-alist' or are added
by filter functions.  See `debpaste-action' for details."
  :type '(alist :key-type symbol :value-type string)
  :group 'debpaste)

(defun debpaste-get-command-name (cmd)
  "Return a name (string) of a command CMD."
  (cdr (assoc cmd debpaste-command-alist)))

(defun debpaste-get-param-name (param-symbol)
  "Return a name of a parameter PARAM-SYMBOL."
  (cdr (assoc param-symbol debpaste-param-alist)))

(defun debpaste-get-param-symbol (param-name)
  "Return a symbol of a parameter PARAM-NAME."
  (car (rassoc param-name debpaste-param-alist)))

(defun debpaste-get-param-description (param-symbol)
  "Return a description of a parameter PARAM-NAME."
  (cdr (assoc param-symbol debpaste-param-description-alist)))

(defun debpaste-get-param-val (param info)
  "Return a value of a parameter PARAM from paste info INFO."
  (cdr (assoc param info)))


;;; General filters for processing info alist

(defcustom debpaste-date-format
  "%Y-%m-%d %T"
  "Time format used to represent submit and expire dates of a paste.
For information about time formats, see `format-time-string'."
  :type 'string
  :group 'debpaste)

(defun debpaste-filter-intern (info)
  "Return INFO with names of parameters replaced with symbols.
For names and symbols of parameters, see `debpaste-param-alist'."
  (delq nil
        (mapcar (lambda (param)
                  (let* ((param-name (car param))
                         (param-symbol (debpaste-get-param-symbol param-name))
                         (param-val (cdr param)))
                    (if param-symbol
                        (cons param-symbol param-val)
                      (message "Warning: paste server has returned unknown parameter %s.  It will be omitted."
                               param-name)
                      nil)))
                info)))

(defun debpaste-filter-error-check (info)
  "Check INFO for server errors.
Return INFO."
  (if (= 0 (debpaste-get-param-val 'ret info))
      info
    (error "Server error: %s" (debpaste-get-param-val 'status info))))

(defun debpaste-filter-url (info)
  "Add \"http:\" string to url parameters.
Return modified info."
  (mapc (lambda (param)
          (let ((param-name (symbol-name (car param)))
                (param-val (cdr param)))
            (and (string-match "url$" param-name)
                 (setcdr param (concat "http:" param-val)))))
        info)
  info)

(defun debpaste-filter-date (info)
  "Format expiration and submit dates with `debpaste-date-format'.
Add `expire-date' symbol to the info alist.
Return modified info."
  (let ((submit-time (date-to-time
                      (debpaste-get-param-val 'submit-date info)))
        (expire-time (debpaste-get-param-val 'expire-sec info)))
    (setq expire-time
          (if (equal expire-time -1)
              "never"
            (format-time-string debpaste-date-format
                                (time-add submit-time
                                          (seconds-to-time expire-time)))))
    (setcdr (assoc 'submit-date info)
            (format-time-string debpaste-date-format submit-time))
    (add-to-list 'info (cons 'expire-date expire-time))))


;;; Languages and major-modes

;; you can help with this, if you know what server language can be
;; used for highlighting a particular major-mode or what major-mode
;; suits a language better
(defcustom debpaste-language-alist
  '(("abap")
    ("antlr")
    ("antlr-as")
    ("antlr-cpp" . c++-mode)
    ("antlr-csharp" . csharp-mode)
    ("antlr-java" . java-mode)
    ("antlr-objc" . objc-mode)
    ("antlr-perl" . perl-mode)
    ("antlr-python" . python-mode)
    ("antlr-ruby" . ruby-mode)
    ("apacheconf")
    ("applescript")
    ("as")
    ("as3")
    ("aspx-cs")
    ("aspx-vb")
    ("basemake")
    ("bash" . sh-mode)
    ("bash" . shell-mode)
    ("bat")
    ("bbcode")
    ("befunge")
    ("boo")
    ("brainfuck")
    ("c" . c-mode)
    ("c-objdump")
    ("cheetah")
    ("clojure" . clojure-mode)
    ("common-lisp" . lisp-mode)
    ("console")
    ("control")
    ("cpp" . c++-mode)
    ("cpp-objdump" . c++-mode)
    ("csharp" . csharp-mode)
    ("css" . css-mode)
    ("css+django" . css-mode)
    ("css+erb" . css-mode)
    ("css+genshitext" . css-mode)
    ("css+mako" . css-mode)
    ("css+myghty" . css-mode)
    ("css+php" . css-mode)
    ("css+smarty" . css-mode)
    ("cython" . python-mode)
    ("d")
    ("d-objdump")
    ("delphi" . delphi-mode)
    ("diff" . diff-mode)
    ("django" . python-mode)
    ("dpatch")
    ("dylan")
    ("erb")
    ("erl")
    ("erlang" . erlang-mode)
    ("evoque")
    ("fortran" . fortran-mode)
    ("gas")
    ("genshi")
    ("genshitext")
    ("glsl" . glsl-mode)
    ("gnuplot" . gnuplot-mode)
    ("groff" . nroff-mode)
    ("haskell" . haskell-mode)
    ("html" . html-mode)
    ("html+cheetah" . html-mode)
    ("html+django" . html-mode)
    ("html+evoque" . html-mode)
    ("html+genshi" . html-mode)
    ("html+mako" . html-mode)
    ("html+myghty" . html-mode)
    ("html+php" . html-mode)
    ("html+smarty" . html-mode)
    ("ini" . conf-colon-mode)
    ("ini" . conf-mode)
    ("ini" . conf-space-mode)
    ("ini" . conf-unix-mode)
    ("ini" . conf-windows-mode)
    ("ini" . conf-xdefaults-mode)
    ("io")
    ("irc")
    ("java" . java-mode)
    ("js" . js-mode)
    ("js+cheetah" . js-mode)
    ("js+django" . js-mode)
    ("js+erb" . js-mode)
    ("js+genshitext" . js-mode)
    ("js+mako" . js-mode)
    ("js+myghty" . js-mode)
    ("js+php" . js-mode)
    ("js+smarty" . js-mode)
    ("jsp")
    ("lhs")
    ("lighty")
    ("llvm")
    ("logtalk")
    ("lua" . lua-mode)
    ("make" . makefile-mode)
    ("make" . makefile-automake-mode)
    ("make" . makefile-gmake-mode)
    ("make" . makefile-makepp-mode)
    ("make" . makefile-bsdmake-mode)
    ("make" . makefile-imake-mode)
    ("mako")
    ("matlab" . matlab-mode)
    ("matlabsession")
    ("minid")
    ("modelica")
    ("moocode")
    ("mupad")
    ("mxml" . nxml-mode)
    ("myghty")
    ("mysql" . sql-mode)
    ("nasm" . asm-mode)
    ("newspeak")
    ("nginx")
    ("numpy")
    ("objdump")
    ("objective-c")
    ("ocaml" . ocaml-mode)
    ("perl" . perl-mode)
    ("php" . php-mode)
    ("pot")
    ("pov")
    ("prolog" . prolog-mode)
    ("py3tb")
    ("pycon")
    ("pytb")
    ("python" . inferior-python-mode)
    ("python" . jython-mode)
    ("python" . python-mode)
    ("python3" . python-mode)
    ("ragel")
    ("ragel-c")
    ("ragel-cpp" . c++-mode)
    ("ragel-d")
    ("ragel-em")
    ("ragel-java" . java-mode)
    ("ragel-objc" . objc-mode)
    ("ragel-ruby" . ruby-mode)
    ("raw")
    ("rb")
    ("rbcon")
    ("rebol")
    ("redcode")
    ("rhtml" . html-mode)
    ("rst")
    ("scala")
    ("scheme" . scheme-mode)
    ("smalltalk")
    ("smarty")
    ("sourceslist")
    ("splus")
    ("sql" . sql-mode)
    ("sqlite3" . sql-mode)
    ("squidconf")
    ("tcl" . tcl-mode)
    ("tcsh")
    ("tex" . tex-mode)
    ("text" . text-mode)
    ("trac-wiki")
    ("vala")
    ("vb.net")
    ("vim")
    ("xml" . nxml-mode)
    ("xml+cheetah" . nxml-mode)
    ("xml+django" . nxml-mode)
    ("xml+erb" . nxml-mode)
    ("xml+evoque" . nxml-mode)
    ("xml+mako" . nxml-mode)
    ("xml+myghty" . nxml-mode)
    ("xml+php" . nxml-mode)
    ("xml+smarty" . nxml-mode)
    ("xslt")
    ("yaml" . yaml-mode))
  "Association list of server languages and major modes."
  :type '(alist :key-type string :value-type symbol)
  :group 'debpaste)

(defun debpaste-get-lang-name (mode)
  "Return a name of the language for a major mode MODE.
If there is no association for the MODE in
`debpaste-language-alist', return `debpaste-paste-language'."
  (or (car (rassoc mode debpaste-language-alist))
      debpaste-paste-language))

(defun debpaste-get-lang-mode (name)
  "Return a major mode of the paste language NAME.
If there is no association for the NAME in
`debpaste-language-alist', return `fundamental-mode'"
  (or (cdr (assoc name debpaste-language-alist))
      'fundamental-mode))


;;; Debpaste buffers

(defcustom debpaste-paste-buffer-name-regexp
  "^\\*debpaste [0-9]+\\*$"
  "Regexp matching a debpaste buffer with a paste text.
Used for killing and quitting debpaste buffers."
  :type 'string
  :group 'debpaste)

(defcustom debpaste-info-buffer-name-regexp
  "^\\*debpaste [0-9]+ (info)\\*$"
  "Regexp matching a debpaste buffer with a paste info.
Used for killing and quitting debpaste buffers."
  :type 'string
  :group 'debpaste)

(defcustom debpaste-get-paste-buffer-name-function
  'debpaste-get-paste-buffer-name-default
  "Function returning the name of a buffer with a paste.
This function should accept one argument (ID of a paste)."
  :type 'function
  :group 'debpaste)

(defcustom debpaste-get-info-buffer-name-function
  'debpaste-get-info-buffer-name-default
  "Function returning the name of a buffer with a paste info.
This function should accept one argument (ID of a paste)."
  :type 'function
  :group 'debpaste)

(defun debpaste-get-paste-buffer-name-default (id)
  "Return the default name of a buffer for the paste ID."
  (format "*debpaste %s*" id))

(defun debpaste-get-info-buffer-name-default (id)
  "Return the default name of a buffer for the paste ID info."
  (format "*debpaste %s (info)*" id))

(defun debpaste-get-posted-info-buffer-name (id)
  "Return the name of a buffer for the posted paste ID info."
  (format "*debpaste %s (posted info)*" id))

(defun debpaste-get-paste-buffer-name (id)
  "Return the name of a buffer for the paste ID.
Use `debpaste-get-paste-buffer-name-function'."
  (funcall debpaste-get-paste-buffer-name-function id))

(defun debpaste-get-info-buffer-name (id)
  "Return the name of a buffer for the paste ID info.
Use `debpaste-get-info-buffer-name-function'."
  (funcall debpaste-get-info-buffer-name-function id))

;; wild name, isn't it?
(defun debpaste-debpaste-bufferp (buffer-or-name)
  "Return non-nil if BUFFER-OR-NAME is a debpaste buffer.
BUFFER-OR-NAME must be either a string (buffer name) or a buffer."
  (let ((name (if (bufferp buffer-or-name)
                  (buffer-name buffer-or-name)
                buffer-or-name)))
    (or (string-match debpaste-paste-buffer-name-regexp name)
        (string-match debpaste-info-buffer-name-regexp name))))

(defun debpaste-kill-paste-buffers (id)
  "Kill existed buffers created for the paste ID."
  (let ((bufs (list (debpaste-get-paste-buffer-name id)
                    (debpaste-get-info-buffer-name  id))))
    (mapc (lambda (buf) (and buf (kill-buffer buf)))
          (mapcar 'get-buffer bufs))))

(defun debpaste-kill-all-buffers ()
  "Kill all debpaste buffers.
Buffers are defined by `debpaste-paste-buffer-name-regexp' and
`debpaste-info-buffer-name-regexp'."
  (interactive)
  (mapc (lambda (buf)
          (and (debpaste-debpaste-bufferp buf)
               (kill-buffer buf)))
        (buffer-list))
  (message "All debpaste buffers were killed."))

(defun debpaste-kill-buffers ()
  "Kill some debpaste buffers.

If current buffer is a debpaste one, kill buffer(s) with this
paste; with \\[universal-argument] kill all debpaste buffers;
otherwise prompt for a paste ID."
  (interactive)
  (if (equal current-prefix-arg '(4))
      (debpaste-kill-all-buffers)
    (debpaste-kill-paste-buffers
     (or (and (local-variable-p 'debpaste-info)
              (debpaste-get-param-val 'id debpaste-info))
         (read-string "Kill buffers with paste ID: ")))))

(defun debpaste-quit-buffers ()
  "Bury debpaste buffers and delete window with additional info.
Buffers are defined by `debpaste-paste-buffer-name-regexp' and
`debpaste-info-buffer-name-regexp'."
  (interactive)
  (mapc (lambda (win)
          ;; `select-window' is essential, otherwise (bury-buffer buf)
          ;; will not bury buffer
          (select-window win)
          (let ((buf (window-buffer win)))
            (and (debpaste-debpaste-bufferp buf)
                 (bury-buffer))))
        (window-list)))


;;; Displaying info with paste parameters

(defcustom debpaste-info-buffer-format "%s: %s\n"
  "String used to format each parameter for info displayed in buffer.
It should contain 2 '%s'-sequences for a description and a value."
  :type 'string
  :group 'debpaste)

(defcustom debpaste-info-buffer-params
  '(id status submitter submit-date expire-date)
  "List of parameters that will appear in info displayed in buffer.
Parameters are symbols from `debpaste-param-description-alist'."
  :type '(repeat symbol)
  :group 'debpaste)

(defcustom debpaste-info-minibuffer-format "%s: %s\n"
  "String used to format each parameter for info displayed in minibuffer.
It should contain 2 '%s'-sequences for a description and a value."
  :type 'string
  :group 'debpaste)

(defcustom debpaste-info-minibuffer-params
  '(submitter submit-date expire-date)
  "List of parameters that will appear in info displayed in minibuffer.
Parameters are symbols from `debpaste-param-description-alist'."
  :type '(repeat symbol)
  :group 'debpaste)

(defcustom debpaste-ignore-empty-params t
  "If non-nil, do not display empty parameters of a paste info."
  :type 'boolean
  :group 'debpaste)

(defvar-local debpaste-info nil
  "Alist with additional info for the current paste.

Car of each assoc is a symbol from `debpaste-param-description-alist';
cdr - is a value of that parameter.")
(put 'debpaste-info 'permanent-local t) ; (info "(elisp) Creating Buffer-Local")

(defun debpaste-get-info (paste-buf)
  "Return alist containing additional paste info for buffer PASTE-BUF.

PASTE-BUF should be a buffer with received paste (it should have
a local-buffer `debpaste-info' variable)."
  (with-current-buffer paste-buf
    (if (local-variable-p 'debpaste-info)
        debpaste-info
      (error "%s is not a debpaste buffer" paste-buf))))

(defun debpaste-get-info-string (info params fmt)
  "Return a string containing paste info INFO.

PARAMS is a list of parameters included in a returned string.  If
it is not specified, show all info parameters (respecting
`debpaste-ignore-empty-params').

FMT is a string to format descriptions and values of parameters.

Parameters and their descriptions got from
`debpaste-param-description-alist'."
  (unless params
    (setq params (mapcar #'car info)))
  (mapconcat (lambda (param)
               (let* ((desc (debpaste-get-param-description param))
                      (val (debpaste-get-param-val param info)))
                 (if (and debpaste-ignore-empty-params
                          (null val))
                     ""                 ; delete empty params
                   (format fmt desc (or val "")))))
             params
             ""))

(defun debpaste-display-info-in-buffer (info &optional params)
  "Display paste info INFO in a separate buffer.
Return INFO.

Interactively display info for the current debpaste buffer, use
`debpaste-info-buffer-params' for PARAMS.

Use `debpaste-info-buffer-format' to format displayed info.
See `debpaste-get-info-string' for description of PARAMS."
  (interactive
   (list (debpaste-get-info (current-buffer))
         debpaste-info-buffer-params))
  (let* ((info-str (debpaste-get-info-string
                    info params debpaste-info-buffer-format))
         (id (debpaste-get-param-val 'id info))
         (buf-name (debpaste-get-info-buffer-name id)))
    (unless (get-buffer buf-name)
      (with-current-buffer (get-buffer-create buf-name)
        (insert info-str)
        (text-mode) ;; i don't like this
        (view-mode) ;; and this (any suggestions?)
        (goto-char (point-min))))
    (let ((win (get-buffer-window buf-name)))
      (if win
          (select-window win)
        (display-buffer buf-name '((display-buffer-same-window))))))
  info)

(defun debpaste-display-info-in-minibuffer (info &optional params)
  "Display paste info INFO in the minibuffer.
Return INFO.

Interactively display info for the current debpaste buffer, use
`debpaste-info-minibuffer-params' for PARAMS.

Use `debpaste-info-minibuffer-format' to format displayed info.
See `debpaste-get-info-string' for description of PARAMS."
  (interactive
   (list (debpaste-get-info (current-buffer))
         debpaste-info-minibuffer-params))
  (message (debpaste-get-info-string
            info params debpaste-info-minibuffer-format))
  info)


;;; Displaying received paste

(defcustom debpaste-received-filter-functions
  '(debpaste-filter-intern debpaste-filter-error-check
    debpaste-add-id-to-info debpaste-filter-url debpaste-filter-date
    debpaste-display-received-paste debpaste-display-received-info)
  "List of functions for filtering info returned after receiving a paste.
See `debpaste-action' for details."
  :type '(repeat function)
  :group 'debpaste)

(defun debpaste-add-id-to-info (info)
  "Add id parameter to the INFO.
Return modified info."
  ;; id parameter is vital for info; as the server doesn't return it,
  ;; we add it here using `paste-id' (`debpaste-display-paste' should
  ;; bother about this variable)
  (or (debpaste-get-param-val 'id info)
      (add-to-list 'info (cons 'id paste-id)))
  info)

(defun debpaste-display-received-info (info)
  "Display info about received paste.
Return INFO."
  (debpaste-display-info-in-minibuffer
   info debpaste-info-minibuffer-params))

(defun debpaste-display-received-paste (info)
  "Display text parameter from INFO in a debpaste buffer.
Return INFO.
Store additional info (without paste text) in a buffer-local
`debpaste-info' variable."
  (let ((buf (get-buffer-create (debpaste-get-paste-buffer-name id)))
        (paste-text (debpaste-get-param-val 'text info))
        (paste-info (delete-if (lambda (param) (equal (car param) 'text))
                               info)))
    (with-current-buffer buf
      (erase-buffer)
      (insert paste-text)
      (setq debpaste-info paste-info))
    (let ((win (get-buffer-window buf)))
      (if win
          (select-window win)
        (display-buffer buf '((display-buffer-same-window))))))
  info)

;;;###autoload
(defun debpaste-display-paste (id)
  "Receive and display a paste with numeric or string ID."
  (interactive "sPaste ID: ")
  (when (numberp id)
    (setq id (number-to-string id)))
  (let ((paste-id id))
    (debpaste-action :cmd 'get-paste
                     :opts (list id)
                     :filters debpaste-received-filter-functions)))


;;; Adding (posting) a paste

(defcustom debpaste-posted-filter-functions
  '(debpaste-filter-intern debpaste-filter-error-check
    debpaste-filter-url debpaste-save-last-posted-info
    debpaste-url-to-kill-ring debpaste-display-posted-info)
  "List of functions for filtering info returned after posting a paste.
See `debpaste-action' for details."
  :type '(repeat function)
  :group 'debpaste)

(defcustom debpaste-completing-read-function
  'ido-completing-read
  "Function for reading a string in the minibuffer.
It is used to prompt for paste options.
Usual values are: `completing-read' or `ido-completing-read'."
  :type 'function
  :group 'debpaste)

(defcustom debpaste-user-name "anonymous"
  "Default user name used for a posting paste."
  :type 'string
  :group 'debpaste)

(defcustom debpaste-paste-language "text"
  "Default language used for a posting paste.
It is used if there is no association for current major mode in
`debpaste-language-alist'."
  :type 'string
  :group 'debpaste)

(defcustom debpaste-expire-time (* 24 3600)
  "Default expiration time (in seconds) for a posting paste."
  :type 'integer
  :group 'debpaste)

(defcustom debpaste-expire-time-alist
  `((3600           . "1 hour")
    (,(* 12 3600)   . "12 hours")
    (,(* 24 3600)   . "1 day")
    (,(* 3 24 3600) . "3 days")
    (,(* 7 24 3600) . "7 days")
    (-1             . "never"))
  "Association list of time values (in seconds) and strings for prompting."
  :type '(alist :key-type integer :value-type string)
  :group 'debpaste)

(defcustom debpaste-paste-is-hidden nil
  "If non-nil, post hidden pastes (not shown on a frontpage)."
  :type 'boolean
  :group 'debpaste)

(defcustom debpaste-prompted-paste-options nil
  "List of prompted options for a posting paste.

If list, prompt for values of options specified in this list and
use default values for other options.  Each option from the list
is one of these symbols: `user', `expire-sec', `lang', `hidden'.

If nil, use default values for all paste options without
prompting."
  :type '(repeat symbol)
  :group 'debpaste)

(defun debpaste-prompt-for-user-name ()
  "Prompt for and return user name for a posting paste."
  (funcall debpaste-completing-read-function
           "User name: " nil nil nil debpaste-user-name))

(defun debpaste-prompt-for-expire-time ()
  "Prompt for and return expiration time for a posting paste."
  (let ((time (funcall debpaste-completing-read-function
                       "Expiration time (seconds or completion value): "
                       (mapcar #'cdr debpaste-expire-time-alist))))
    (or (car (rassoc time debpaste-expire-time-alist))
        (string-to-number time))))

(defun debpaste-prompt-for-lang ()
  "Prompt for and return language for a posting paste."
  (funcall debpaste-completing-read-function
           "Language: "
           (mapcar #'car debpaste-language-alist)
           nil nil nil nil (debpaste-get-lang-name major-mode)))

(defun debpaste-prompt-for-hidden ()
  "Prompt for and return hidden option (t or nil) for a posting paste."
  (y-or-n-p "Hidden paste?"))

(defun debpaste-url-to-kill-ring (info)
  "Add view-url parameter from INFO to kill-ring.
Return INFO."
  (kill-new (debpaste-get-param-val 'view-url info))
  info)

(defun debpaste-display-posted-info (info)
  "Display info about posted paste.
Return INFO."
  (message "Your paste has been posted successfully.\n%s"
           (debpaste-get-info-string info '(download-url delete-url)
                                     debpaste-info-minibuffer-format))
  info)

;;;###autoload
(defun debpaste-paste-region (start end)
  "Send a region to the paste server.
Interactively use current region.

Prompt for additional options specified in
`debpaste-prompted-paste-options'.
With \\[universal-argument] prompt for all paste options."
  (interactive "r")
  (let ((opt-list (if (equal current-prefix-arg '(4))
                      '(user expire-sec lang hidden)
                    debpaste-prompted-paste-options)))
    (cl-flet ((get-opt-val (opt default prompt-fun &rest args)
                           (if (member opt opt-list)
                               (apply prompt-fun args)
                             default)))
      (let ((text (buffer-substring-no-properties start end))
            (user (get-opt-val 'user debpaste-user-name
                               'debpaste-prompt-for-user-name))
            (expire (get-opt-val 'expire-sec debpaste-expire-time
                                 'debpaste-prompt-for-expire-time))
            (lang (get-opt-val 'lang (debpaste-get-lang-name major-mode)
                               'debpaste-prompt-for-lang))
            (hidden (if (get-opt-val 'hidden debpaste-paste-is-hidden
                                     'debpaste-prompt-for-hidden)
                        1
                      0)))
        (debpaste-action :cmd 'add-paste
                         :opts (list text user expire lang hidden)
                         :filters debpaste-posted-filter-functions)))))

;;;###autoload
(defun debpaste-paste-buffer (buffer-or-name)
  "Send a buffer BUFFER-OR-NAME to the paste server.
Interactively use current buffer."
  (interactive (list (current-buffer)))
  (with-current-buffer buffer-or-name
    (debpaste-paste-region (point-min) (point-max))))

(defvar debpaste-last-posted-info nil
  "Alist with info about last posted paste.")

(defun debpaste-save-last-posted-info (info)
  "Set `debpaste-last-posted-info' to INFO value.
Return INFO."
  (setq debpaste-last-posted-info info))

(defun debpaste-display-last-posted-info ()
  "Display info about last posted paste in a separate buffer."
  (interactive)
  (if debpaste-last-posted-info
      (let ((debpaste-get-info-buffer-name-function
             'debpaste-get-posted-info-buffer-name))
        (debpaste-display-info-in-buffer
         debpaste-last-posted-info
         '(id digest view-url download-url delete-url)))
    (message "You have not posted pastes in this session.")))


;;; Deleting a paste

(defcustom debpaste-deleted-filter-functions
  '(debpaste-filter-intern debpaste-filter-error-check
    debpaste-display-deleted-info)
  "List of functions for filtering info returned after deleting a paste.
See `debpaste-action' for details."
  :type '(repeat function)
  :group 'debpaste)

(defun debpaste-display-deleted-info (info)
  "Display info about deleted paste.
Return INFO."
  (debpaste-display-info-in-minibuffer
   info '(status)))

;;;###autoload
(defun debpaste-delete-paste (digest)
  "Delete a paste with specified DIGEST from the paste server.
You receive DIGEST after posting the paste."
  (interactive "sPaste digest: ")
  (debpaste-action :cmd 'del-paste
                   :opts (list digest)
                   :filters debpaste-deleted-filter-functions))

(provide 'debpaste)

;;; debpaste.el ends here
