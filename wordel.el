;;; wordel.el --- An Elisp implementation of "Wordle" (aka "Lingo")  -*- lexical-binding: t; -*-

;; Copyright (C) 2022

;; Author:  Nicholas Vollmer <iarchivedmywholelife@gmail.com>
;; URL: https://github.com/progfolio/wordel
;; Created: Janurary 13, 2022
;; Keywords: games
;; Package-Requires: ((emacs "27.1"))
;; Version: 0.0.0

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Have fun!

;;; Code:
(require 'cl-lib)
(require 'text-property-search)

;;; Custom Options
(defgroup wordel nil
  "Elisp implementation of `wordle` aka `lingo`"
  :group 'games
  :prefix "wordel-")

(defcustom wordel-word-length 5
  "Length of the puzzle word.
If it is an int, words will be that length.
It may also be a cons sell of form: (MIN . MAX)."
  :type (or 'int 'cons))

(defcustom wordel-attempt-limit 6
  "Number of attempts allowed before game over."
  :type 'int)

(defcustom wordel-words-function #'wordel-local-words
  "Function used to retrieve the candidate word list.
It takes no words and returns a list of strings."
  :type 'function)

(defcustom wordel-word-file "/usr/share/dict/words"
  "File containing puzzle word candidates.
Each candidate should be on a separate line."
  :type 'file)

(defcustom wordel-illegal-characters "[^A-Za-z]"
  "Regular expression matching illegal word characters.
These are deleted from a puzzle word character."
  :type 'regexp)

;;;; Variables
(defvar wordel-buffer "*wordel*" "Name of the wordel buffer.")

;;;; Faces
(defface wordel-correct
  '((t (:background "#538D4E")))
  "Face for a guessed letter which matches its position in the puzzle word.")

(defface wordel-almost
  '((t (:background "#bf9f3b")))
  "Face for a guessed letter which is included in the puzzle word.")

(defface wordel-box
  '((t (:box (:line-width -4 :color "black" :style released-button))))
  "Default face for a wordel letter.")

(defface wordel-current-box
  '((t (:box (:line-width -4 :color "orange" :style released-button))))
  "Default face for a wordel letter.")

(defface wordel-spacer
  '((t (:width ultra-condensed :height 0.1 :background nil)))
  "Face for space between letter boxes.")

(defface wordel-default
  '((t ( :weight ultra-bold :background "#3A3A3C" :foreground "#D7DADC" :height 3.0)))
  "Default face for a wordel letter.")

(defface wordel-error
  '((t ( :inherit compilation-error)))
  "Default face for a wordel error message.")

(defun wordel-legal-p (word)
  "Return t if WORD is a legal word, nil otherwise."
  (let* ((min (or (car-safe wordel-word-length) wordel-word-length))
         (max (or (cdr-safe wordel-word-length) wordel-word-length)))
    (and (<= min (length word) max)
         (string-match-p "[AEIOUYaeiouy]" word)
         (not (string-match-p wordel-illegal-characters word)))))

(defun wordel-local-words ()
  "Return a puzzle word from `wordel-word-file'."
  (with-temp-buffer
    (insert-file-contents wordel-word-file)
    (mapcar #'upcase (cl-remove-if-not #'wordel-legal-p
                                       (split-string (buffer-string) "\n")))))

(defun wordel--word (candidates)
  "Select a random word from CANDIDATES."
  (nth (random (length candidates)) candidates))

(defun wordel--comparison (guess subject)
  "Return propertized GUESS character list compared against SUBJECT."
  (let ((subjects (split-string subject "" 'omit-nulls))
        (guesses  (split-string guess   "" 'omit-nulls))
        (matches  nil))
    (cl-loop for i from 0 to (1- (length guesses))
             for g = (nth i guesses)
             for s = (nth i subjects)
             do (put-text-property 0 1 'hint
                                   (cond
                                    ((string-match-p g s)
                                     (push g matches) 'wordel-correct)
                                    ((and (string-match-p g subject)
                                          (not (string-match-p g guess (+ i 1)))
                                          (not (member g matches)))
                                     'wordel-almost)
                                    (t nil))
                                   g)
             collect g)))

(defun wordel--pad (char)
  "Visually pad CHAR."
  (let ((spacer (propertize " " 'display '(space :width 1.5))))
    (concat spacer char spacer)))

(defun wordel--tile (string &optional box)
  "Return a tile from STRING.
If BOX is non-nil, outline the tile with it."
  (let ((face (list :inherit (list 'wordel-default))))
    (when-let ((hint (get-text-property 0 'hint string)))
      (push hint (cadr face)))
    (push (or box 'wordel-box) (cadr face))
    (propertize (wordel--pad string) 'face face)))

(defun wordel--row (chars &optional current)
  "Return a row of tiles from CHARS.
If CURRENT is non-nil, mark row as current."
  (string-join
   (cl-loop for i from 0 to (1- (length chars))
            for c = (nth i chars)
            collect (wordel--tile (if current (propertize c 'index i) c)
                                  (when current 'wordel-current-box)))
   (propertize " " 'face 'wordel-spacer)))

(defun wordel--board (rows)
  "Return a board string from ROWS."
  (mapconcat (lambda (row) (propertize row 'cursor-intangible t))
             rows "\n"))

(defun wordel--position-cursor (column)
  "Position cursor in COLUMN of current-row.
COLUMNs are zero indexed."
  (goto-char (point-min))
  (text-property-search-forward 'current-row)
  (beginning-of-line)
  (let ((box nil))
    (dotimes (_ (1+ column))
      (setq box (text-property-search-forward 'index)))
    (when box (goto-char (prop-match-beginning box)))))

(defun wordel--display-char (char)
  "Display CHAR in current box."
  (with-current-buffer wordel-buffer
    (with-silent-modifications
      (let ((p (point))) (put-text-property p (1+ p) 'display char)))))

(defun wordel--current-word ()
  "Return current row's word."
  (save-excursion
    (wordel--position-cursor 0)
    (let ((row (buffer-substring (line-beginning-position) (line-end-position))))
      (mapconcat (lambda (string)
                   (if-let ((char (get-text-property 0 'display string))
                            ((stringp char)))
                       char
                     ""))
                 (split-string row "" 'omit-nils)))))

(defun wordel--display-message (string &rest objects)
  "Display a message in the UI message area.
STRING and OBJECTS are passed to `format', which see."
  (with-current-buffer wordel-buffer
    (save-excursion
      (goto-char (point-min))
      (if-let ((area (text-property-search-forward 'message-area)))
          (with-silent-modifications
            (put-text-property (prop-match-beginning area) (prop-match-end area)
                               'display (apply #'format string objects)))
        (error "Unable to locate message area")))))

(defun wordel--display-error (string &rest objects)
  "Display an error in the UI message area.
STRING and OBJECTS are passed to `format', which see."
  (wordel--display-message
   "%s" (propertize (apply #'format string objects) 'face 'wordel-error)))

(defun wordel-read-word (words)
  "Read word and test against WORDS."
  (let ((index 0)
        done
        result)
    (while (not done)
      (wordel--position-cursor index)
      ;; @HACK: Is there a better way to catch a quit signal from read-event?
      ;; Thought I could wrap the call in a `condition-case', but that doesn't seem
      ;; do the trick on its own. ~ NV 2022-01-14
      (let ((event (let ((inhibit-quit t))
                     (read-event "wordel reading events. Press C-g to quit game."))))
        (wordel--display-message "%s" " ") ;;clear messages
        (pcase event
          (?\C-g  (setq done t result nil))
          ('return
           (let ((word (wordel--current-word)))
             (if (and (wordel-legal-p word)
                      (member word words))
                 (setq done t result word)
               (wordel--display-error "Word not in dictionary: %S" word))))
          ('backspace (wordel--display-char " ")
                      (when (> index 0) (cl-decf index)))
          ((pred characterp)
           (let ((s (char-to-string event)))
             (if (string-match-p wordel-illegal-characters s)
                 (wordel--display-error "Illegal character: %S" s)
               (wordel--display-char (upcase s))
               (when (< index (1- wordel-word-length))
                 (cl-incf index))))))))
    result))

(defun wordel--new-game ()
  "Initialize a new game."
  (let* ((words (or (funcall wordel-words-function)
                    (error "Unable to retrieve candidate words with %S"
                           wordel-words-function)))
         (word (or (wordel--word words)
                   (error "Unable to find a puzzle word")))
         (limit wordel-attempt-limit)
         (attempts 0)
         (rows nil)
         (blanks (make-list (length word) " "))
         (outcome nil))
    (with-current-buffer (get-buffer-create wordel-buffer)
      (pop-to-buffer-same-window wordel-buffer)
      (while (not outcome)
        (wordel-mode)
        (goto-char (point-min))
        (with-silent-modifications
          (erase-buffer)
          (insert (wordel--board
                   (append rows
                           (when (< attempts limit)
                             (append
                              (list (wordel--row blanks 'current))
                              (make-list (- limit (1+ attempts)) (wordel--row blanks))))))
                  "\n\n"
                  (propertize " " 'message-area t)))
        (cond
         ((and (> attempts 0)
               (string= (replace-regexp-in-string " " "" (car (last rows))) word))
          (setq outcome 'win))
         ((>= attempts limit)
          (setq outcome 'lose))
         (t (cl-incf attempts)
            (let ((guess (wordel-read-word words)))
              (if guess
                  (setq rows (append
                              rows
                              (list (wordel--row (wordel--comparison guess word)))))
                (setq outcome 'quit)
                ;; Leaving cursor in the board gives false impression that game is on.
                (goto-char (point-max))))))
        (pcase outcome
          ('win  (wordel--display-message "You WON!"))
          ('lose (wordel--display-message "YOU LOST! Word was %S"     word))
          ('quit (wordel--display-message "The word was %S, quitter." word))))
      outcome)))

(define-derived-mode wordel-mode special-mode "Wordel"
  "A word game based on 'Wordle' and/or 'Lingo'.

\\{wordel-mode-map}")

;;; Key bindngs
(define-key wordel-mode-map (kbd "r") 'wordel)

;;;###autoload
(defun wordel ()
  "Play wordel."
  (interactive)
  (wordel--new-game))

(defun wordel-marathon--append-message (string &rest objects)
  "Append STRING to game message.
STRING and OBJECT are passed to `format', which see."
  (with-current-buffer wordel-buffer
    (save-excursion
      (with-silent-modifications
        (goto-char (point-min))
        (let* ((anchor (text-property-search-forward 'message-area))
               (beg    (prop-match-beginning anchor)))
          (put-text-property beg (prop-match-end anchor) 'display
                             (concat
                              (get-text-property beg 'display)
                              (apply #'format string objects))))))))

;;;###autoload
(defun wordel-marathon ()
  (interactive)
  (let ((wordlen 3)
        (attempts 11)
        (rounds 0)
        (outcome nil))
    (while (not (member outcome '(quit lose champion)))
      (setq outcome
            (let ((wordel-word-length   (cl-incf wordlen))
                  (wordel-attempt-limit (if (zerop (mod rounds 3))
                                            (cl-decf attempts)
                                          attempts)))
              (condition-case _
                  (wordel--new-game)
                ((error) 'champion))))
      (cl-incf rounds))
    (apply #'wordel-marathon--append-message
           (pcase outcome
             ('quit     (list "\nHad enough, eh? Final Score: %d" (cl-decf rounds)))
             ('lose     (list"\nFinal Score: %d" rounds))
             ('champion (list "\nYOU BEAT THE DICTIONARY! Final Score: %d" rounds))))))


(provide 'wordel)
;;; wordel.el ends here
