(define-module (ipdb services)
  #:use-module (bigchaindb)
  #:use-module (tendermint)
  #:use-module (gnu services)
  #:use-module (gnu services shepherd)
  #:use-module (gnu system shadow)
  #:use-module (gnu packages admin)
  #:use-module (gnu packages databases)
  #:use-module (guix build-system trivial)
  #:use-module (guix build union)
  #:use-module (guix build utils)
  #:use-module (guix modules)
  #:use-module (guix packages)
  #:use-module (guix records)
  #:use-module (guix gexp)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 match)
  #:export (<bigchaindb-configuration>
            bigchaindb-configuration
            bigchaindb-configuration?
            bigchaindb-configuration-bigchaindb
            bigchaindb-configuration-config-file
            bigchaindb-configuration-data-directory
            bigchaindb-service-type

	    <tendermint-configuration>
            tendermint-configuration
            tendermint-configuration?
            tendermint-configuration-tendermint
            tendermint-configuration-config-file
            tendermint-configuration-data-directory
            tendermint-service-type))

;;
;; Locally generated tednermint files
;;
;; (let* ((conn (open-connection))
;;        (tm-output (derivation->output-path (package-derivation conn tendermint-bin)))
;;        (tm-binary (string-concatenate `(,tm-output "/bin/tendermint"))))
;;   (invoke tm-binary "init")
;;   (close-connection conn))


;;;
;;; BigchaindbDB
;;;

(define %default-bigchaindb-configuration-file
  (plain-file "bigchaindb-config.json"
   "{
    \"server\": {
        \"bind\": \"0.0.0.0:9984\",
        \"loglevel\": \"info\",
        \"workers\": null
    },
    \"wsserver\": {
        \"scheme\": \"ws\",
        \"host\": \"localhost\",
        \"port\": 9985,
        \"advertised_scheme\": \"ws\",
        \"advertised_host\": \"localhost\",
        \"advertised_port\": 9985
    },
    \"tendermint\": {
        \"host\": \"localhost\",
        \"port\": 26657
    },
    \"database\": {
        \"backend\": \"localmongodb\",
        \"connection_timeout\": 5000,
        \"max_tries\": 3,
        \"ssl\": false,
        \"ca_cert\": null,
        \"certfile\": null,
        \"keyfile\": null,
        \"keyfile_passphrase\": null,
        \"crlfile\": null,
        \"host\": \"localhost\",
        \"port\": 27017,
        \"name\": \"bigchain\",
        \"replicaset\": null,
        \"login\": null,
        \"password\": null
    },
    \"log\": {
        \"file\": \"/var/log/bigchaindb/bigchaindb.log\",
        \"error_file\": \"/var/log/bigchaindb/bigchaindb-errors.log\",
        \"level_console\": \"info\",
        \"level_logfile\": \"info\",
        \"datefmt_console\": \"%Y-%m-%d %H:%M:%S\",
        \"datefmt_logfile\": \"%Y-%m-%d %H:%M:%S\",
        \"fmt_console\": \"[%(asctime)s] [%(levelname)s] (%(name)s) %(message)s (%(processName)-10s - pid: %(process)d)\",
        \"fmt_logfile\": \"[%(asctime)s] [%(levelname)s] (%(name)s) %(message)s (%(processName)-10s - pid: %(process)d)\",
        \"granular_levels\": {}
    },
    \"CONFIGURED\": true
   }"))


(define-record-type* <bigchaindb-configuration>
  bigchaindb-configuration make-bigchaindb-configuration
  bigchaindb-configuration?
  (bigchaindb             bigchaindb-configuration-bigchaindb
                       (default bigchaindb))
  (config-file         bigchaindb-configuration-config-file
                       (default %default-bigchaindb-configuration-file))
  (data-directory      bigchaindb-configuration-data-directory
                       (default "/var/lib/bigchaindb")))

(define %bigchaindb-accounts
  (list (user-group (name "bigchaindb") (system? #t))
        (user-account
         (name "bigchaindb")
         (group "bigchaindb")
         (system? #t)
         (comment "BigchainDB server user")
         (home-directory "/var/lib/bigchaindb")
         (shell (file-append shadow "/sbin/nologin")))))

(define bigchaindb-activation
  (match-lambda
    (($ <bigchaindb-configuration> bigchaindb config-file data-directory)
     #~(begin
         (use-modules (guix build utils))
         (let ((user (getpwnam "bigchaindb")))
           (for-each
            (lambda (directory)
              (mkdir-p directory)
              (chown directory
                     (passwd:uid user) (passwd:gid user)))
            '("/var/run/bigchandb" #$data-directory)))))))

(define bigchaindb-shepherd-service
  (match-lambda
    (($ <bigchaindb-configuration> bigchaindb config-file data-directory)
     (shepherd-service
      (provision '(bigchaindb))
      (documentation "Run the BigchainDB service.")
      (requirement '(user-processes loopback tendermint mongodb)) ; add tendermint dep
      (start #~(make-forkexec-constructor
                `(,(string-append #$bigchaindb "/bin/bigchaindb")
                  "--config"
                  ,#$config-file)
                #:user "bigchaindb"
                #:group "bigchaindb"
                #:pid-file "/var/run/bigchaindb/pid"
		#:directory #$data-directory
                #:log-file "/var/log/bigchaindb.log"))
      (stop #~(make-kill-destructor))))))


(define bigchaindb-service-type
  (service-type
   (name 'bigchaindb)
   (description "Run the BigchaindDB server.")
   (extensions
    (list (service-extension shepherd-root-service-type
                             (compose list
                                      bigchaindb-shepherd-service))
          (service-extension activation-service-type
                             bigchaindb-activation)
          (service-extension account-service-type
                             (const %bigchaindb-accounts))))
   (default-value
     (bigchaindb-configuration))))


;;
;; Tendermint service type
;;
(define %default-tendermint-configuration-file
  (plain-file "tendermint-config.json"
   ""))


(define-record-type* <tendermint-configuration>
  tendermint-configuration make-tendermint-configuration
  tendermint-configuration?
  (tendermint          tendermint-configuration-tendermint
                       (default tendermint-bin))
  (config-file         tendermint-configuration-config-file
                       (default %default-tendermint-configuration-file))
  (data-directory      tendermint-configuration-data-directory
                       (default "/var/lib/tendermint")))

(define %tendermint-accounts
  (list (user-group (name "tendermint") (system? #t))
        (user-account
         (name "tendermint")
         (group "tendermint")
         (system? #t)
         (comment "Tendermint user")
         (home-directory "/var/lib/tendermint")
         (shell (file-append shadow "/sbin/nologin")))))

(define tendermint-activation
  (match-lambda
    (($ <tendermint-configuration> tendermint-bin config-file data-directory)
     #~(begin
         (use-modules (guix build utils))
	 (let ((port (open-file)))
	   (display #$tendermint-bin port)
	   (display (string-append #$tendermint-bin "/bin/tendermint")))
	 (let ((user (getpwnam "tendermint")))
           (for-each
            (lambda (directory)
              (mkdir-p directory)
              (chown directory
                     (passwd:uid user) (passwd:gid user)))
            '("/var/run/tendermint" #$data-directory)))))))

(define tendermint-shepherd-service
  (match-lambda
    (($ <tendermint-configuration> tendetmint-bin config-file data-directory)
     (shepherd-service
      (provision '(tendermint))
      (documentation "Run the Tendermint service.")
      (requirement '(user-processes loopback))
      (start #~(begin
		 (let ((port (open-file "whereami-exec" "w")))
		   (display #$data-directory port)
		   (close-port port))
		 (make-forkexec-constructor
                  `(,(string-append #$tendermint-bin "/bin/tendermint")
                    "node"
 		    "--p2p.laddr=\"tcp://0.0.0.0:26656\""
                    "--proxy_app=\"tcp://0.0.0.0:26658\""
                    "--consensus.create_empty_blocks=false"
                    "--p2p.pex=false")
                  #:user "tendermint"
                  #:group "tendermint"
                  #:pid-file "/var/run/tendermint/pid"
		  #:directory #$data-directory
		  #:log-file "/var/log/tendermint.log"
		  #:environment-variables '("HOME=/var/lib/tendermint"
					    ;; TMPATH probably not
					    ;; available in early versions
					    "TMPATH=/var/lib/tendermint"))))
      (stop #~(make-kill-destructor))))))

(define tendermint-service-type
  (service-type
   (name 'tendermint)
   (description "Run the Tendermint server.")
   (extensions
    (list (service-extension shepherd-root-service-type
                             (compose list
                                      tendermint-shepherd-service))
          (service-extension activation-service-type
                             tendermint-activation)
          (service-extension account-service-type
                             (const %tendermint-accounts))))
   (default-value
     (tendermint-configuration))))
