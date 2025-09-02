#!/bin/bash

# Fix Pigeon duplicate declarations by renaming classes in Clipboard generated files
# This script should be run after Pigeon generation to avoid redeclaration errors

set -e

CLIPBOARD_FILE="ios/Runner/Clipboard/ClipboardMessages.g.swift"
SYNC_FILE="ios/Runner/Sync/Messages.g.swift"

echo "🔧 Fixing Pigeon duplicate declarations..."

if [ ! -f "$CLIPBOARD_FILE" ]; then
    echo "❌ Clipboard file not found: $CLIPBOARD_FILE"
    exit 1
fi

if [ ! -f "$SYNC_FILE" ]; then
    echo "❌ Sync file not found: $SYNC_FILE"
    exit 1
fi

# Create backup
cp "$CLIPBOARD_FILE" "${CLIPBOARD_FILE}.backup"

echo "📝 Renaming duplicated declarations in Clipboard file..."

# Rename PigeonError to ClipboardPigeonError
sed -i '' 's/final class PigeonError: Error/final class ClipboardPigeonError: Error/g' "$CLIPBOARD_FILE"
sed -i '' 's/PigeonError(/ClipboardPigeonError(/g' "$CLIPBOARD_FILE"

# Rename wrapResult to clipboardWrapResult
sed -i '' 's/private func wrapResult/private func clipboardWrapResult/g' "$CLIPBOARD_FILE"
sed -i '' 's/wrapResult(/clipboardWrapResult(/g' "$CLIPBOARD_FILE"

# Rename wrapError to clipboardWrapError
sed -i '' 's/private func wrapError/private func clipboardWrapError/g' "$CLIPBOARD_FILE"
sed -i '' 's/wrapError(/clipboardWrapError(/g' "$CLIPBOARD_FILE"

# Rename isNullish to clipboardIsNullish
sed -i '' 's/private func isNullish/private func clipboardIsNullish/g' "$CLIPBOARD_FILE"
sed -i '' 's/isNullish(/clipboardIsNullish(/g' "$CLIPBOARD_FILE"

# Rename nilOrValue to clipboardNilOrValue
sed -i '' 's/private func nilOrValue/private func clipboardNilOrValue/g' "$CLIPBOARD_FILE"
sed -i '' 's/nilOrValue(/clipboardNilOrValue(/g' "$CLIPBOARD_FILE"

# Rename any other private helper functions that might be duplicated
sed -i '' 's/private func createConnectionError/private func clipboardCreateConnectionError/g' "$CLIPBOARD_FILE"
sed -i '' 's/createConnectionError(/clipboardCreateConnectionError(/g' "$CLIPBOARD_FILE"

# Rename any other utility functions that might conflict
sed -i '' 's/private func isNullish/private func clipboardIsNullish/g' "$CLIPBOARD_FILE"
sed -i '' 's/isNullish(/clipboardIsNullish(/g' "$CLIPBOARD_FILE"

# Check if there are any remaining conflicts and report them
echo "🔍 Checking for remaining potential conflicts..."

# List any remaining functions that might conflict
echo "📋 Functions in Clipboard file:"
grep -E "^(private )?func " "$CLIPBOARD_FILE" | head -10

echo "📋 Functions in Sync file:"
grep -E "^(private )?func " "$SYNC_FILE" | head -10

echo "✅ Successfully renamed duplicated declarations in Clipboard file"
echo "📁 Backup created at: ${CLIPBOARD_FILE}.backup"
echo "🔍 You can review changes with: diff ${CLIPBOARD_FILE}.backup $CLIPBOARD_FILE"
echo ""
echo "💡 If you still get redeclaration errors, check the function lists above"
echo "   and add more rename rules to this script as needed."
