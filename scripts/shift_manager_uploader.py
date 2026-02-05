#!/usr/bin/env python3
"""
Shift Manager CSV Uploader

This script watches a local folder for Shift Manager Summary CSV files
and uploads them to Firebase Storage for processing by a Cloud Function.

Usage:
    python shift_manager_uploader.py

Configuration:
    - Place firebase-service-account.json in the same directory
    - Adjust WATCH_FOLDER and STORAGE_BUCKET as needed
"""

import os
import sys
import logging
from datetime import datetime
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, storage

# =============================================================================
# Configuration
# =============================================================================

# Folder to watch for CSV files
WATCH_FOLDER = r"C:\Users\jenno\OneDrive\Desktop\Shift Manager Summary"

# Firebase Storage bucket (without gs:// prefix)
STORAGE_BUCKET = "schedulehq-cf87f.firebasestorage.app"

# Storage path for uploads
STORAGE_PATH = "shift_manager_imports"

# Path to service account credentials (relative to this script)
SERVICE_ACCOUNT_PATH = Path(__file__).parent / "firebase-service-account.json"

# Log file path
LOG_FILE = Path(__file__).parent / "shift_manager_upload.log"

# =============================================================================
# Logging Setup
# =============================================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# =============================================================================
# Firebase Initialization
# =============================================================================

def initialize_firebase():
    """Initialize Firebase Admin SDK with service account credentials."""
    if not SERVICE_ACCOUNT_PATH.exists():
        logger.error(f"Service account file not found: {SERVICE_ACCOUNT_PATH}")
        logger.error("Please download from Firebase Console > Project Settings > Service Accounts")
        sys.exit(1)
    
    try:
        cred = credentials.Certificate(str(SERVICE_ACCOUNT_PATH))
        firebase_admin.initialize_app(cred, {
            "storageBucket": STORAGE_BUCKET
        })
        logger.info("Firebase initialized successfully")
    except Exception as e:
        logger.error(f"Failed to initialize Firebase: {e}")
        sys.exit(1)

# =============================================================================
# File Upload Functions
# =============================================================================

def get_csv_files(folder: str) -> list[Path]:
    """Get all CSV files in the specified folder."""
    folder_path = Path(folder)
    
    if not folder_path.exists():
        logger.warning(f"Watch folder does not exist: {folder}")
        return []
    
    csv_files = list(folder_path.glob("*.csv"))
    logger.info(f"Found {len(csv_files)} CSV file(s) in {folder}")
    return csv_files

def upload_file(local_path: Path) -> bool:
    """
    Upload a file to Firebase Storage.
    
    Args:
        local_path: Path to the local file
        
    Returns:
        True if upload successful, False otherwise
    """
    try:
        bucket = storage.bucket()
        
        # Create storage path: shift_manager_imports/filename.csv
        blob_name = f"{STORAGE_PATH}/{local_path.name}"
        blob = bucket.blob(blob_name)
        
        # Upload file
        blob.upload_from_filename(str(local_path), content_type="text/csv")
        
        logger.info(f"Uploaded: {local_path.name} -> gs://{STORAGE_BUCKET}/{blob_name}")
        return True
        
    except Exception as e:
        logger.error(f"Failed to upload {local_path.name}: {e}")
        return False

def delete_local_file(file_path: Path) -> bool:
    """
    Delete a local file after successful upload.
    
    Args:
        file_path: Path to the file to delete
        
    Returns:
        True if deletion successful, False otherwise
    """
    try:
        file_path.unlink()
        logger.info(f"Deleted local file: {file_path.name}")
        return True
    except Exception as e:
        logger.error(f"Failed to delete {file_path.name}: {e}")
        return False

# =============================================================================
# Main Process
# =============================================================================

def process_files():
    """Main function to process all CSV files in the watch folder."""
    logger.info("=" * 60)
    logger.info(f"Shift Manager Uploader started at {datetime.now()}")
    logger.info("=" * 60)
    
    # Get CSV files
    csv_files = get_csv_files(WATCH_FOLDER)
    
    if not csv_files:
        logger.info("No CSV files to process")
        return
    
    # Process each file
    uploaded = 0
    failed = 0
    
    for csv_file in csv_files:
        logger.info(f"Processing: {csv_file.name}")
        
        if upload_file(csv_file):
            # Delete local file after successful upload
            if delete_local_file(csv_file):
                uploaded += 1
            else:
                # File uploaded but couldn't delete - still count as success
                uploaded += 1
                logger.warning(f"File uploaded but local copy remains: {csv_file.name}")
        else:
            failed += 1
    
    # Summary
    logger.info("-" * 60)
    logger.info(f"Processing complete: {uploaded} uploaded, {failed} failed")
    logger.info("=" * 60)

def main():
    """Entry point."""
    # Initialize Firebase
    initialize_firebase()
    
    # Process files
    process_files()

if __name__ == "__main__":
    main()
