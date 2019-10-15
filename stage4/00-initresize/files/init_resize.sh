#!/bin/sh

reboot_pi () {
  umount /boot
  mount / -o remount,ro
  sync
  echo b > /proc/sysrq-trigger
  sleep 5
  exit 0
}

check_commands () {
  if ! command -v whiptail > /dev/null; then
      echo "whiptail not found"
      sleep 5
      return 1
  fi
  for COMMAND in grep cut sed parted fdisk findmnt partprobe; do
    if ! command -v $COMMAND > /dev/null; then
      FAIL_REASON="$COMMAND not found"
      return 1
    fi
  done
  return 0
}

get_variables () {
  ROOT_PART_DEV=$(findmnt / -o source -n)
  ROOT_PART_NAME=$(echo "$ROOT_PART_DEV" | cut -d "/" -f 3)
  ROOT_DEV_NAME=$(echo /sys/block/*/"${ROOT_PART_NAME}" | cut -d "/" -f 4)
  ROOT_DEV="/dev/${ROOT_DEV_NAME}"
  ROOT_PART_NUM=$(cat "/sys/block/${ROOT_DEV_NAME}/${ROOT_PART_NAME}/partition")

  BOOT_PART_DEV=$(findmnt /boot -o source -n)
  BOOT_PART_NAME=$(echo "$BOOT_PART_DEV" | cut -d "/" -f 3)
  BOOT_DEV_NAME=$(echo /sys/block/*/"${BOOT_PART_NAME}" | cut -d "/" -f 4)
  BOOT_PART_NUM=$(cat "/sys/block/${BOOT_DEV_NAME}/${BOOT_PART_NAME}/partition")

  DATA_PART_DEV=$(findmnt /home/pi/RevvyFramework/user -o source -n)
  DATA_PART_NAME=$(echo "$DATA_PART_DEV" | cut -d "/" -f 3)
  DATA_DEV_NAME=$(echo /sys/block/*/"${DATA_PART_NAME}" | cut -d "/" -f 4)
  DATA_PART_NUM=$(cat "/sys/block/${DATA_DEV_NAME}/${DATA_PART_NAME}/partition")

  OLD_DISKID=$(fdisk -l "$ROOT_DEV" | sed -n 's/Disk identifier: 0x\([^ ]*\)/\1/p')

  DATA_DEV_SIZE=$(cat "/sys/block/${DATA_DEV_NAME}/size")
  TARGET_END=$((DATA_DEV_SIZE - 1))

  PARTITION_TABLE=$(parted -m "$ROOT_DEV" unit s print | tr -d 's')

  LAST_PART_NUM=$(echo "$PARTITION_TABLE" | tail -n 1 | cut -d ":" -f 1)

  DATA_PART_LINE=$(echo "$PARTITION_TABLE" | grep -e "^${DATA_PART_NUM}:")
  DATA_PART_START=$(echo "$DATA_PART_LINE" | cut -d ":" -f 2)
  DATA_PART_END=$(echo "$DATA_PART_LINE" | cut -d ":" -f 3)
}

fix_partuuid() {
  DISKID="$(fdisk -l "$ROOT_DEV" | sed -n 's/Disk identifier: 0x\([^ ]*\)/\1/p')"

  sed -i "s/${OLD_DISKID}/${DISKID}/g" /etc/fstab
  sed -i "s/${OLD_DISKID}/${DISKID}/" /boot/cmdline.txt
}

check_variables () {
  if [ "$BOOT_DEV_NAME" != "$ROOT_DEV_NAME" ]; then
      FAIL_REASON="Boot and root partitions are on different devices"
      return 1
  fi

  if [ "$DATA_PART_NUM" -ne "$LAST_PART_NUM" ]; then
    FAIL_REASON="Data partition should be last partition"
    return 1
  fi

  if [ "$DATA_PART_END" -gt "$TARGET_END" ]; then
    FAIL_REASON="Data partition runs past the end of device"
    return 1
  fi

  if [ ! -b "$ROOT_DEV" ] || [ ! -b "$DATA_PART_DEV" ] || [ ! -b "$ROOT_PART_DEV" ] || [ ! -b "$BOOT_PART_DEV" ] ; then
    FAIL_REASON="Could not determine partitions"
    return 1
  fi
}

main () {
  get_variables

  if ! check_variables; then
    return 1
  fi

  if [ "$DATA_PART_END" -eq "$TARGET_END" ]; then
    reboot_pi
  fi

  if ! parted -m "$ROOT_DEV" u s resizepart "$DATA_PART_NUM" yes "$TARGET_END"; then
    FAIL_REASON="Data partition resize failed"
    return 1
  fi

  partprobe "$ROOT_DEV"
  fix_partuuid

  return 0
}

mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t tmpfs tmp /run
mkdir -p /run/systemd

mount /boot
mount / -o remount,rw
mount /home/pi/RevvyFramework/user

sed -i 's| init=/usr/lib/revvy-config/init_resize\.sh||' /boot/cmdline.txt
sed -i 's| sdhci\.debug_quirks2=4||' /boot/cmdline.txt

sync

echo 1 > /proc/sys/kernel/sysrq

if ! check_commands; then
  reboot_pi
fi

if main; then
  whiptail --infobox "Resized data filesystem. Rebooting in 5 seconds..." 20 60
  sleep 5
else
  sleep 5
  whiptail --msgbox "Could not expand filesystem, please try raspi-config or rc_gui.\n${FAIL_REASON}" 20 60
fi

reboot_pi