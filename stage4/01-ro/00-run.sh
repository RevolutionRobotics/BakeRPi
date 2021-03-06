#!/bin/bash -e

on_chroot << EOF

echo "  Remove unused packages"
sudo apt-get remove --purge -y triggerhappy logrotate cron
# remove avahi-daemon?
# apt-get remove --purge -y avahi-daemon
# update logging (from medium/swlh). should do? logread to see logs
sudo apt-get install -y busybox-syslogd
sudo apt-get remove --purge -y rsyslog
sudo apt-get autoremove --purge -y

echo "  ROize randomseed"
# DOES NOT EXIST; rm /var/lib/systemd/random-seed
ln -s /tmp/random-seed /var/lib/systemd/random-seed
sed -i 's#ExecStart#ExecStartPre=/bin/echo "" >/tmp/random-seed\nExecStart#'  /lib/systemd/system/systemd-random-seed.service

echo "  Relocate dhcp related files"
mv /etc/resolv.conf /var/run/resolv.conf && ln -s /var/run/resolv.conf /etc/resolv.conf
mv /var/lib/dhcp /var/run/dhcp && ln -s /var/run/dhcp /var/lib/dhcp
rm -rf /var/lib/dhcpcd5 && ln -s /var/run /var/lib/dhcpcd5
sed -i 's#PIDFile=/run/dhcpcd.pid#PIDFile=/var/run/dhcpcd.pid#' /etc/systemd/system/dhcpcd5.service
sed -i 's#PIDFile=/run/dhcpcd.pid#PIDFile=/var/run/dhcpcd.pid#' /lib/systemd/system/dhcpcd.service
# Disable wait for dhcp
rm -f /etc/systemd/system/dhcpcd.service.d/wait.conf

# Relocate /var/spool?
## Not needed to relocate as all packages using it were removed (cron, rsyslog)
#rm -rf /var/spool
#ln -s /tmp /var/spool

echo "  Stop mask systemd timers/services"
systemctl disable systemd-tmpfiles-clean.timer systemd-tmpfiles-clean
systemctl disable cron
systemctl mask systemd-update-utmp systemd-update-utmp-runlevel 
systemctl mask systemd-rfkill systemd-rfkill.socket  # enable/disable wireless devices, bluetooth
systemctl disable systemd-fsck-root

echo "  ROize prelogin-qr"
rm -rf /etc/issue
ln -s /tmp/etc-issue /etc/issue

echo "  ROize bluetooth"
# NOTE: hacky, /var/run/bluetooth would be nicer, but requires creating dir on every boot
ln -s /var/run /var/lib/bluetooth

#FIXME: regenerate_ssh_host_keys.service wants to write to /etc/ssh so we disable it for now
/usr/bin/ssh-keygen -A -v
systemctl disable regenerate_ssh_host_keys

EOF
