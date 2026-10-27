#!/bin/sh
# Start the Bitwarden desktop app hidden, but only once the login keyring is
# unlocked. Bitwarden reads its fingerprint-unlock key from the keyring once,
# at startup; started too early it finds the keyring locked, falls back to the
# master password, and the Firefox extension loses its biometric button.
# Gives up waiting after 30s (a fingerprint login leaves the keyring locked)
# and starts Bitwarden anyway.

i=0
while [ "$i" -lt 60 ]; do
	locked=$(busctl --user get-property org.freedesktop.secrets \
		/org/freedesktop/secrets/collection/login \
		org.freedesktop.Secret.Collection Locked 2>/dev/null)
	[ "$locked" = "b false" ] && break
	sleep 0.5
	i=$((i + 1))
done

exec bitwarden --autostart
