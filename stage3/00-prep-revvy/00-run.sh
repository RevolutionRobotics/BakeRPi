#!/bin/bash -e

echo " Start installing things that are unique to revvy "

on_chroot << EOF
echo "  Enable raw sockets for python for BT "
setcap 'cap_net_raw,cap_net_admin+eip' \$(readlink -f \$(which python3))

echo "  Enable i2c module "
echo "i2c-dev" >> /etc/modules

# disable swapping
sudo dphys-swapfile swapoff
sudo dphys-swapfile uninstall
sudo update-rc.d dphys-swapfile remove
sudo apt purge -y dphys-swapfile

# disable services that are not needed
sudo systemctl disable systemd-update-utmp.service
sudo systemctl mask systemd-update-utmp.service
sudo systemctl disable apt-daily.service
sudo systemctl mask apt-daily.service
sudo systemctl disable apt-daily.timer
sudo systemctl disable apt-daily-upgrade.service
sudo systemctl mask apt-daily-upgrade.service
sudo systemctl disable apt-daily-upgrade.timer
sudo systemctl disable man-db.service
sudo systemctl disable man-db.timer
sudo systemctl disable systemd-timesyncd.service
sudo systemctl disable wpa_supplicant.conf
sudo systemctl disable keyboard-setup.service
sudo systemctl disable graphical.target

sudo pip3 install pyqrcode
EOF

echo "  Install production support script"
install -m 755 files/serial.sh            "${ROOTFS_DIR}/home/pi/"

echo "  Deploy python service "
install -m 644 files/revvy.service        "${ROOTFS_DIR}/etc/systemd/system/revvy.service"

git clone https://github.com/RevolutionRobotics/RevvyLauncher.git
echo "  Copying launcher to ${ROOTFS_DIR}/home/pi/RevvyFramework"
cp -r RevvyLauncher/src "${ROOTFS_DIR}/home/pi/RevvyFramework"
echo "  Deleting launcher sources "
rm -rf RevvyLauncher

echo " Downloading latest framework source "
git clone https://github.com/RevolutionRobotics/RevvyFramework.git
cd RevvyFramework

echo " Creating install package "
python3 -m tools.create_package
echo "  Copying install files to ${ROOTFS_DIR}/home/pi/RevvyFramework/user/ble/"

on_chroot << EOF
echo "  Setting permissions on data directory "
chown pi:pi -R "/home/pi/RevvyFramework"
chmod 755 -R /home/pi/RevvyFramework/

mkdir /home/pi/RevvyFramework/default_packages
mkdir -p /home/pi/RevvyFramework/user/ble
EOF

cp install/framework.data "${ROOTFS_DIR}/home/pi/RevvyFramework/user/ble/2.data"
cp install/framework.meta "${ROOTFS_DIR}/home/pi/RevvyFramework/user/ble/2.meta"

cd ..
echo "  Deleting framework sources "
rm -rf RevvyFramework

on_chroot << EOF
echo "  Install the included package "
python3 /home/pi/RevvyFramework/launch_revvy.py --install-only --install-default
echo "  Enable Revvy service "
systemctl enable revvy
EOF
