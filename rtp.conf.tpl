; rtp.conf template

[general]
;
; RTP start and end ports
;
rtpstart=__RTP_START__
rtpend=__RTP_END__

; Other common RTP settings (optional)
; rtcp_mux=yes ; Enable RTCP multiplexing if your endpoints support it
; ice_support=yes ; Enable ICE support if needed for NAT traversal
; stunaddr=stun.l.google.com:19302 ; Example STUN server, if ICE is enabled
