# Shrink RAW Image Script

This script automates the process of reducing the size of a RAW disk image by resizing its partitions and filesystem. It supports both GPT and MBR partition tables and ensures the image is optimized for minimal size without compromising data integrity.

---

## **Features**
- Validates dependencies and input file format.
- Maps partitions using `kpartx` for easier manipulation.
- Resizes the filesystem and partitions to the minimum required size.
- Shrinks the RAW image file to match the resized partition.
- Repairs GPT partition headers if necessary.

---

## **Requirements**
The script requires the following commands to be installed on your system:
- `qemu-img`
- `kpartx`
- `fdisk`
- `e2fsck`
- `resize2fs`
- `gdisk`
- `parted`

To install these tools on Ubuntu/Debian:
```bash
sudo apt update
sudo apt install qemu-utils kpartx util-linux gdisk parted
```

---

## **Usage**
```bash
./shrink_raw_image.sh <raw_image_file>
```

### **Example**
```bash
./shrink_raw_image.sh test-image.raw
```

---

## **How It Works**
1. **Dependency Check:** Ensures all required tools are installed.
2. **Input Validation:** Verifies the input file exists and is in RAW format.
3. **Partition Mapping:** Maps the RAW image partitions for easier manipulation.
4. **Filesystem Resizing:** Shrinks the filesystem to its minimum size.
5. **Partition Resizing:** Adjusts the partition to match the new filesystem size.
6. **Image Shrinking:** Reduces the RAW image file size to match the resized partition.
7. **Cleanup:** Unmaps partitions and repairs GPT headers if required.

---

## **Output**
- The script logs each step of the operation, including errors and warnings.
- If the image is already optimized for minimal size, the script will exit without performing any operation.

---

## **Cautions**
- Always create a backup of your RAW image before running this script.
- Avoid using this script on mounted or active disk images.

---

## **Troubleshooting**
- If the script fails, check the logs for specific error messages.
- Ensure the dependencies are properly installed and accessible.

---
 🚀