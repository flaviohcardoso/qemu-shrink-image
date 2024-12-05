#!/bin/bash

# Global variable to store mapped partitions
FILE=""
PARTITION_MAPPER=""
PARTITION_TYPE=""
MIN_SIZE=0

# Function to check if required commands are available
check_dependencies() {
    echo "Checking dependencies..."
    for cmd in qemu-img kpartx fdisk e2fsck resize2fs gdisk parted; do
        if ! command -v $cmd &> /dev/null; then
            echo "Error: Command $cmd is not installed. Please install it before proceeding."
            exit 1
        fi
    done
    echo "All dependencies are installed."
}

# Function to validate the input file
validate_input() {
    if [[ -z "$FILE" ]]; then
        echo "Usage: $0 <raw_image_file>"
        exit 1
    fi
    if [[ ! -f "$FILE" ]]; then
        echo "Error: File $FILE does not exist."
        exit 1
    fi
    echo "Validating file format..."
    local format=$(qemu-img info --output=json "$FILE" | grep -o '"format": "[^"]*"' | cut -d':' -f2 | tr -d ' "')
    if [[ "$format" != "raw" ]]; then
        echo "Error: File $FILE is not in RAW format."
        exit 1
    fi
    echo "Input file is valid and in RAW format: $FILE"
}

# Function to create the mapping using kpartx
map_partitions() {
    echo "Mapping partitions..."
    local mapper_output=$(kpartx -av "$FILE")
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to map partitions for $FILE."
        exit 1
    fi
    # Extract the loop device and partition paths from kpartx output
    PARTITION_MAPPER=$(echo "$mapper_output" | grep 'add map' | awk '{print $3}' | sed 's/^/\/dev\/mapper\//')
    if [[ -z "$PARTITION_MAPPER" ]]; then
        echo "Error: Could not find loop device or partition mapper for $FILE."
        exit 1
    fi
    echo "Partitions mapped successfully."
}

# Function to delete the mapping created by kpartx
delete_mapping() {
    echo "Deleting mappings for $FILE..."
    kpartx -d "$FILE"
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to delete mappings for $FILE."
        exit 1
    fi
    PARTITION_MAPPER=""
    echo "Mappings deleted successfully."
}

# Function validates the integrity of the filesystem
validate_filesystem() {
    echo "Validating the filesystem on $PARTITION_MAPPER..."
    e2fsck -f -y "$PARTITION_MAPPER"
} 

# Function to calculate the minimum filesystem size and validate if resizing is needed
calculate_size_filesystem() {
    echo "Calculating minimum filesystem size..."

    # Calculate the minimum size in blocks and convert to MB
    MIN_SIZE=$(resize2fs -P "$PARTITION_MAPPER" | awk '{printf "%.0f\n", ($NF * 4096 + 1024 * 1024 - 1) / (1024*1024)}')
    echo "Calculated minimum size: ${MIN_SIZE}M"

    # Get the current size of the image in MB
    local current_image_size_mb
    current_image_size_mb=$(qemu-img info --output=json "$FILE" | grep -o '"virtual-size": [0-9]*' | awk '{print $2 / 1024 / 1024}')

    # Allow a margin of 1% to account for rounding differences
    local margin=1 # 1% margin
    local allowed_min_size_mb=$((MIN_SIZE + MIN_SIZE * margin / 100))

    # Check if the image size is already close to the minimum
    if (( $(echo "$current_image_size_mb <= $allowed_min_size_mb" | bc -l) )); then
        echo "Image size ($current_image_size_mb MB) is already close to the minimum filesystem size ($MIN_SIZE MB)."
        delete_mapping
        exit 0
    fi
}

# Function to resize filesystem
resize_filesystem() {
    resize2fs "$PARTITION_MAPPER" "${MIN_SIZE}M"
    if [[ $? -eq 0 ]]; then
        echo "Filesystem resized successfully to ${MIN_SIZE}M"
    else
        echo "Error: Failed to resize to ${MIN_SIZE}M"
        delete_mapping
        exit 1
    fi
}

# Function to resize the partition using parted
resize_partition() {
    echo "Resizing partition to ${MIN_SIZE}M using parted..."
    echo yes | parted "$FILE" ---pretend-input-tty resizepart 1 ${MIN_SIZE}M
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to resize the partition to ${MIN_SIZE}M."
        delete_mapping
        exit 1
    fi
    local output
    output=$(parted -s "$FILE" print 2>&1)
    # Extract partition table type
    PARTITION_TYPE=$(echo "$output" | grep "Partition Table" | awk '{print $3}')

    echo "Partition resized successfully to ${MIN_SIZE}M."
}

# Function to shrink the RAW image
shrink_raw_image() {
    echo "Resizing RAW image to ${MIN_SIZE}M"
    qemu-img resize --shrink -f raw "$FILE" ${MIN_SIZE}M
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to resize RAW image."
        delete_mapping
        exit 1
    fi
    echo "RAW image resized successfully to ${MIN_SIZE}M"
}

# Function to repair GPT partition using gdisk
repair_gpt_partition() {
    echo "Repairing GPT partition for $FILE using gdisk..."
    gdisk "$FILE" <<EOF
x
e
w
Y
EOF

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to repair GPT partition table for $FILE."
        exit 1
    fi
    echo "GPT partition table repaired successfully."
}

# Main function
main() {
    # Check for required dependencies
    check_dependencies

    FILE=$1
    # Validates the input file, ensuring it exists and is in RAW format.
    validate_input

    # Maps the partitions using kpartx and stores the mapper information.
    map_partitions

    # Validates the integrity of the filesystem before making changes.
    validate_filesystem

    # Calculates the minimum size required for the filesystem.
    calculate_size_filesystem

    # Resizes the filesystem to the minimum size.
    resize_filesystem

    # Resizes the partition to match the new filesystem size.
    resize_partition

    # Validates the filesystem again after resizing.
    validate_filesystem

    # Shrinks the RAW image file to the new partition size.
    shrink_raw_image

    # Deletes the partition mappings created by kpartx.
    delete_mapping

    # Check if the partition table is GPT and repair if necessary
    if [[ "$PARTITION_TYPE" == "gpt" ]]; then
        echo "Detected GPT partition. Repairing GPT headers..."
        repair_gpt_partition
    fi

    echo "** Shrink operation completed successfully. **"
}

# Execute the script with provided arguments
main "$@"