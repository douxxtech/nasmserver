; strings.asm - all strings for this program

section .text
    str_space                       db " ", 0
    str_space_len                   equ $ - str_space - 1

    str_quotation_mark              db 0x22, 0  ; '"'
    str_quotation_mark_len          equ $ - str_quotation_mark - 1

    str_two_dots                    db ":", 0
    str_two_dots_len                equ $ - str_two_dots - 1

    str_slash                       db "/", 0
    str_slash_len                   equ $ - str_slash - 1


    ; startup banner
    str_started_nasmserver          db "Started the NASMServer static files HTTP server.", 0xa, 0
    str_started_nasmserver_len      equ $ - str_started_nasmserver - 1


    ; startup checks
    str_startup_ok                  db "Startup checks passed", 0
    str_startup_ok_len              equ $ - str_startup_ok - 1

    str_check_docroot_missing       db "document_root does not exist or is not a directory", 0
    str_check_docroot_missing_len   equ $ - str_check_docroot_missing - 1

    str_check_docroot_perms         db "document_root is not readable/accessible", 0
    str_check_docroot_perms_len     equ $ - str_check_docroot_perms - 1

    str_check_errordoc_missing      db "Errordoc file not found (requests will get empty error pages)", 0
    str_check_errordoc_missing_len  equ $ - str_check_errordoc_missing - 1

    str_check_port_privileged       db "Port < 1024 might require root privileges", 0
    str_check_port_privileged_len   equ $ - str_check_port_privileged - 1

    str_str_file_not_opened         db "Failed to open the provided log file (missing permissions?). STDOUT will be used instead.", 0
    str_str_file_not_opened_len     equ $ - str_str_file_not_opened - 1

    str_chroot_noroot               db "Not able to chroot since we're not root", 0
    str_chroot_noroot_len           equ $ - str_chroot_noroot - 1

    str_nobody_noroot               db "Not able to set uid to nobody since we're not root", 0
    str_nobody_noroot_len           equ $ - str_nobody_noroot - 1

    ; startup errors / warnings 
    str_fail_read_env               db "Failed to read the provided configuration file path", 0
    str_fail_read_env_len           equ $ - str_fail_read_env - 1

    str_fail_build_addr             db "Failed to parse the provided BIND_ADDRESS. Make sure to provide a valid IPv4 address.", 0
    str_fail_build_addr_len         equ $ - str_fail_build_addr - 1

    str_fail_socket                 db "Failed to open socket", 0
    str_fail_socket_len             equ $ - str_fail_socket - 1

    str_fail_setsockopt             db "Failed to set socket options", 0
    str_fail_setsockopt_len         equ $ - str_fail_setsockopt - 1

    str_fail_bind                   db "Failed to bind to port", 0
    str_fail_bind_len               equ $ - str_fail_bind - 1

    str_fail_accept                 db "Failed to accept connection", 0
    str_fail_accept_len             equ $ - str_fail_accept - 1

    str_listening_on                db "Listening on ", 0
    str_listening_on_len            equ $ - str_listening_on - 1

    ; request logging
    ; common log format extended
    clfe_missing                    db "-", 0
    clfe_missing_len                equ $ - clfe_missing - 1

    clfe_start_ts                   db "[", 0
    clfe_start_ts_len               equ $ - clfe_start_ts - 1

    clfe_end_ts                     db "]", 0
    clfe_end_ts_len                 equ $ - clfe_end_ts - 1

    clfe_nobytes                    db "0", 0
    clfe_nobytes_len                equ $ - clfe_nobytes - 1

    ; HTTP status messages
    str_status_200                  db "200 OK", 0xa, 0
    str_status_200_len              equ $ - str_status_200 - 1

    str_status_304                  db "304 Not Modified", 0xa, 0
    str_status_304_len              equ $ - str_status_304 - 1

    str_status_400                  db "400 Bad Request", 0xa, 0
    str_status_400_len              equ $ - str_status_400 - 1

    str_status_401                  db "401 Unauthorized", 0xa, 0
    str_status_401_len              equ $ - str_status_401 - 1

    str_status_403                  db "403 Forbidden", 0xa, 0
    str_status_403_len              equ $ - str_status_403 - 1

    str_status_404                  db "404 Not Found", 0xa, 0
    str_status_404_len              equ $ - str_status_404 - 1

    str_status_405                  db "405 Method Not Allowed", 0xa, 0
    str_status_405_len              equ $ - str_status_405 - 1


    ; runtime logs
    str_too_many_concurrent         db "Rejected request: too many concurrent requests", 0
    str_too_many_concurrent_len     equ $ - str_too_many_concurrent - 1

    str_stopping                    db "Stopping... (signal received)", 0
    str_stopping_len                equ $ - str_stopping - 1

    str_child_created_p1            db "Started new child (", 0
    str_child_created_p2            db ") to handle request from ", 0

    str_child_exit_p1               db "Exiting child (", 0
    str_child_exit_p2               db "): request served", 0

    str_method_head                 db "Resolved method to HEAD", 0
    str_method_head_len             equ $ - str_method_head - 1

    str_method_get                  db "Resolved method to GET", 0
    str_method_get_len              equ $ - str_method_get - 1

    str_path_resolved               db "Resolved path to ", 0

    str_dotfile_blocked             db "Dotfile access blocked: ", 0

    str_replying_with_code          db "Replying to request with status code ", 0

    str_sent_bytes_p1               db "Replying to request with ", 0
    str_sent_bytes_p2               db " bytes (body)", 0

    str_process_reaped              db "Process reaped, current count: ", 0

    str_chroot_failed_p1            db "Failed to chroot into ", 0
    str_chroot_failed_p2            db ", continuing anyways...", 0

    str_chroot_succeeded            db "Successfully chroot-ed into ", 0 

    str_errordoc_paths_rebuilt      db "Errordoc paths rebuilt", 0
    str_errordoc_paths_rebuilt_len  equ $ - str_errordoc_paths_rebuilt - 1

    str_nobody_failed               db "Failed to drop privileges to nobody, continuing anyways...", 0
    str_nobody_failed_len           equ $ - str_nobody_failed - 1

    str_nobody_succeeded            db "Successfully dropped privileges to nobody", 0
    str_nobody_succeeded_len        equ $ - str_nobody_succeeded - 1

    str_success_sighandler_p1       db "Successfully registered the ", 0
    str_success_sighandler_p2       db " signal handler", 0

    str_fail_sighandler_p1          db "Failed to register the ", 0
    str_fail_sighandler_p2          db ", continuing anyways...", 0

    str_sighanlder_sigterm          db "SIGTERM", 0
    str_sighanlder_sigint           db "SIGINT", 0
    str_sighanlder_sigchld          db "SIGCHLD", 0

    str_process_started_p1          db "Main process started by UID ", 0
    str_process_started_p2          db " with PID ", 0

    str_config_header               db "Loaded config:", 0
    str_config_docroot              db "  DOCUMENT_ROOT:    ", 0
    str_config_index                db "  INDEX_FILE:       ", 0
    str_config_bindaddr             db "  BIND_ADDRESS:     ", 0
    str_config_port                 db "  PORT:             ", 0
    str_config_maxreqs              db "  MAX_REQUESTS:     ", 0
    str_config_maxage               db "  MAX_AGE:          ", 0
    str_config_lingerto             db "  LINGER_TIMEOUT:   ", 0
    str_config_servername           db "  SERVER_NAME:      ", 0
    str_config_logfile              db "  LOG_FILE:         ", 0
    str_config_loglevel             db "  LOG_LEVEL:        ", 0
    str_config_servedots            db "  SERVE_DOTS:       ", 0
    str_config_usexri               db "  USE_X_REAL_IP:    ", 0
    str_config_usechroot            db "  USE_CHROOT:       ", 0
    str_config_noperms              db "  DROP_PRIVILEGES:  ", 0
    str_config_authrealm            db "  AUTH_REALM:       ", 0
    str_config_authuser             db "  AUTH_USER:        ", 0
    str_config_authpass             db "  AUTH_PASSWORD:    ", 0
    str_config_authpass_set         db "********", 0       ; shown if password is set
    str_config_err400               db "  ERRORDOC_400:     ", 0
    str_config_err401               db "  ERRORDOC_401:     ", 0
    str_config_err403               db "  ERRORDOC_403:     ", 0
    str_config_err404               db "  ERRORDOC_404:     ", 0
    str_config_err405               db "  ERRORDOC_405:     ", 0

    ; CLI / arguments / help
    str_arg_not_recognized_p1       db "Argument '", 0
    str_arg_not_recognized_p1_len   equ $ - str_arg_not_recognized_p1 - 1

    str_arg_not_recognized_p2       db "' is not recognized by NASMServer.", 0xa, \
                                       "Run nasmserver -h to see the list of available flags and arguments.", 0
    str_arg_not_recognized_p2_len   equ $ - str_arg_not_recognized_p2 - 1

    str_flag_e_error                db "Missing value after '-e'. Usage: -e <config.env>", 0
    str_flag_e_error_len            equ $ - str_flag_e_error - 1

    str_help_text                   db "Usage: nasmserver [-h] [-e <config.env>]", 0xa, \
                                       "  -h              show this help", 0xa, \
                                       "  -v              show the current version", 0xa, \
                                       "  -e <config>     path to the .env config file", 0xa, 0
    str_help_text_len               equ $ - str_help_text - 1

    str_version                     db "Server version: ", 0
    str_version_len                 equ $ - str_version - 1