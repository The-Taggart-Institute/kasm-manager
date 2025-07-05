; pjsip.conf template

[transport-udp]
type=transport
protocol=udp
bind=0.0.0.0:__SIP_PORT__ ; Placeholder for SIP port
; local_net=192.168.0.0/16 ; Example: Add local network if needed for NAT handling
; external_media_address=__PUBLIC_IP__ ; Example: Placeholder for public IP if needed
; external_signaling_address=__PUBLIC_IP__ ; Example: Placeholder for public IP if needed

[global]
type=global
user_agent=Dockerized Asterisk Instance __INSTANCE_ID__
debug=yes ; Enable PJSIP debugging

; Anonymous endpoint for basic testing (e.g., call from a SIP client without registration)
[anonymous]
type=endpoint
transport=transport-udp
context=public
disallow=all
allow=ulaw,alaw,gsm
aors=anonymous-aor

[anonymous-aor]
type=aor
max_contacts=1
remove_existing=yes

; Example of a simple trunk (optional, can be expanded)
; [my-sip-trunk]
; type=endpoint
; transport=transport-udp
; context=from-trunk
; disallow=all
; allow=ulaw
; aors=my-sip-trunk-aor
; from_domain=your-provider.com
;
; [my-sip-trunk-aor]
; type=aor
; contact=sip:user@your-provider.com

; Example of a simple internal phone (optional, can be expanded)
; [phone100]
; type=endpoint
; transport=transport-udp
; context=internal
; disallow=all
; allow=ulaw
; auth=auth_phone100
; aors=phone100
;
; [auth_phone100]
; type=auth
; auth_type=userpass
; password=securepassword
; username=phone100
;
; [phone100] ; This is the AOR section for phone100
; type=aor
; max_contacts=1
; remove_existing=yes
