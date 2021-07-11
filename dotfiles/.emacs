;; Initial set up
(set-default-font "Ubuntu Mono-18")
(menu-bar-mode 0)
(tool-bar-mode 0)
(ido-mode 1)

;; smex (meta-x replacement)
(global-set-key (kbd "M-x") 'smex)
(global-set-key (kbd "M-X") 'smex-major-mode-commands)

;; Fix TLS
(setq gnutls-algorithm-priority "NORMAL:-VERS-TLS1.3")

;; Global config for usability and formatting
(global-set-key (kbd "C-x k") 'kill-this-buffer)
(add-hook 'before-save-hook 'delete-trailing-whitespace)
(setq require-final-newline 'visit-save)
(setq backup-directory-alist '((".*" . "~/.emacs.d/backups")))
(setq create-lockfiles 'nil)

;; Replace tabs with spaces except Makefiles
(defun untabify-except-makefiles ()
  (unless (derived-mode-p 'makefile-mode)
          (untabify (point-min) (point-max))))
(add-hook 'before-save-hook 'untabify-except-makefiles)

;; C specific config
(defun my-c-mode-hook ()
  (setq c-basic-offset 4
        c-indent-level 4
        c-default-style "bsd"))
(add-hook 'c-mode-common-hook 'my-c-mode-hook)
(add-hook 'c-mode-common-hook '(lambda () (c-toggle-auto-state 1)))

;; Shell script specific config

(setq sh-basic-offset 2)

;; Packages and Themes
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
;; Comment/uncomment this line to enable MELPA Stable if desired.  See `package-archive-priorities`
;; and `package-pinned-packages`. Most users will not need or want to do this.
;;(add-to-list 'package-archives '("melpa-stable" . "https://stable.melpa.org/packages/") t)
(package-initialize)
(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(custom-enabled-themes (quote (gruber-darker)))
 '(custom-safe-themes
   (quote
    ("5f824cddac6d892099a91c3f612fcf1b09bb6c322923d779216ab2094375c5ee" default)))
 '(package-selected-packages (quote (yasnippet smex gruber-darker-theme magit))))

(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
