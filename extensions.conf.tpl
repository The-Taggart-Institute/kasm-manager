; extensions.conf template

[general]
static=yes
writeprotect=no
clearglobalvars=no

[globals]
INSTANCE_ID=__INSTANCE_ID__ ; Placeholder for instance ID

[default]
; Default context, can be used for internal calls if you define more endpoints

[public]
; Context for calls from the anonymous PJSIP endpoint or unauthenticated sources

; Echo test: Any number starting with 1 and having 4 digits (e.g., 1000)
exten => _1XXX,1,NoOp(Call to echo test from ${CALLERID(all)} on Instance ${INSTANCE_ID})
 same => n,Answer()
 same => n,Wait(1)
 same => n,Echo()
 same => n,Hangup()

; Example: Dialing a number that plays a sound file (if sound files are installed and available)
; exten => 2000,1,NoOp(Call to play sound from ${CALLERID(all)} on Instance ${INSTANCE_ID})
;  same => n,Answer()
;  same => n,Playback(hello-world) ; Requires 'hello-world' sound file
;  same => n,Hangup()

; Example: A simple IVR entry point (can be expanded)
; exten => 3000,1,NoOp(Call to IVR from ${CALLERID(all)} on Instance ${INSTANCE_ID})
;  same => n,Answer()
;  same => n,Wait(1)
;  same => n,Background(enter-ext-of-person) ; Plays a prompt
;  same => n,WaitExten(10) ; Waits 10 seconds for user input

[internal]
; Context for authenticated internal users/phones
; exten => _2XX,1,NoOp(Internal call to ${EXTEN} from ${CALLERID(num)} on Instance ${INSTANCE_ID})
;  same => n,Dial(PJSIP/${EXTEN})
;  same => n,Hangup()

; Include other contexts if needed
; #include "more-extensions.conf"
