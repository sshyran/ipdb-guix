;; This is an operating system configuration for a VM image.
;; Modify it as you see fit and instantiate the changes by running:
;;
;;   guix system reconfigure /etc/config.scm
;;
(set! %load-path (cons "./" %load-path))

(use-modules (tendermint)
             (bigchaindb)
	     (gnu)
	     (guix)
	     (gnu services)
	     (gnu services shepherd)
	     (gnu services databases)
	     (gnu system shadow)
	     (gnu packages screen)
	     (gnu packages admin)
	     (gnu packages databases)
	     (guix build-system trivial)
	     (guix build union)
	     (guix modules)
	     (guix packages)
	     (guix records)
	     (guix gexp)
	     (ice-9 match)
	     (ipdb services)
	     (srfi srfi-1))

(use-service-modules desktop networking ssh xorg)
(use-package-modules bootloaders certs fonts nvi
                     package-management wget xorg)

(define this-file
  (local-file (basename (assoc-ref (current-source-location) 'filename))
              "config.scm"))

(operating-system
  (host-name "ipdb")
  (timezone "Etc/UTC")
  (locale "en_US.utf8")
  (keyboard-layout (keyboard-layout "us" "altgr-intl"))

  ;; Label for the GRUB boot menu.
  (label (string-append "IPDB Node" (package-version guix)))

  (firmware '())

  ;; Below we assume /dev/vda is the VM's hard disk.
  ;; Adjust as needed.
  (bootloader (bootloader-configuration
               (bootloader grub-bootloader)
               (target "/dev/sda")
               (terminal-outputs '(console))))
  (file-systems (cons (file-system
                        (mount-point "/")
                        (device "/dev/sda1")
                        (type "ext4"))
                      %base-file-systems))

  (users (cons (user-account
                (name "guest")
                (comment "Guest")
                (password "")                     ; XXX no password
                (group "users")
                (supplementary-groups '("wheel" "netdev"
                                        "audio" "video")))
               %base-user-accounts))

  ;; Our /etc/sudoers file.  Since 'guest' initially has an empty password,
  ;; allow for password-less sudo.
  (sudoers-file (plain-file "sudoers" "\
root ALL=(ALL) ALL
%wheel ALL=NOPASSWD: ALL\n"))

  (packages (append (list
		     screen
		     font-bitstream-vera
		     nss-certs
		     nvi
		     wget
		     bigchaindb mongodb tendermint-bin)
		    %base-packages))

  (services
   (append (list
		 (service bigchaindb-service-type)
		 (service mongodb-service-type)
		 (service tendermint-service-type)
		 (service openssh-service-type
			  (openssh-configuration
			   (permit-root-login #t)
			   (allow-empty-passwords? #t)))
		 (agetty-service
                  (agetty-configuration
                   (extra-options '("-L"))
                   (baud-rate "115200")
                   (term "vt100")
                   (tty "ttyO0")))
                 ;; Copy this file to /etc/config.scm in the OS.
                 (simple-service 'config-file etc-service-type
                                 `(("config.scm" ,this-file)))
                 ;; Use the DHCP client service rather than NetworkManager.
                 (service dhcp-client-service-type))

           ;; Remove GDM, ModemManager, NetworkManager, and wpa-supplicant,
           ;; which don't make sense in a VM.
           (remove (lambda (service)
                     (let ((type (service-kind service)))
                       (or (memq type
                                 (list gdm-service-type
                                       wpa-supplicant-service-type
                                       cups-pk-helper-service-type
                                       network-manager-service-type
                                       modem-manager-service-type))
                           (eq? 'network-manager-applet
                                (service-type-name type)))))
                   (modify-services %desktop-services
                     (login-service-type config =>
                                         (login-configuration
                                          (inherit config)))))))

  ;; Allow resolution of '.local' host names with mDNS.
  (name-service-switch %mdns-host-lookup-nss))
