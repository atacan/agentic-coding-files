#!/bin/bash

# This script builds a Swift target, captures its output and errors,
# and pipes the result to the 'claude' command for analysis.

# --- Configuration ---
set -euo pipefail

# --- Input Validation ---
show_usage() {
  echo "Usage: $0 [OPTIONS] <target-name>" >&2
  echo "Options:" >&2
  echo "  -p, --platform PLATFORM    Specify platform (macos|ios). Default: macos" >&2
  echo "  -h, --help                  Show this help message" >&2
  echo "" >&2
  echo "Examples:" >&2
  echo "  $0 MyTarget                 # Build for macOS" >&2
  echo "  $0 -p ios MyTarget          # Build for iOS" >&2
}

# Default values
PLATFORM="macos"
TARGET_NAME=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -p|--platform)
      PLATFORM="$2"
      shift 2
      ;;
    -h|--help)
      show_usage
      exit 0
      ;;
    -*)
      echo "Error: Unknown option $1" >&2
      show_usage
      exit 1
      ;;
    *)
      if [ -z "$TARGET_NAME" ]; then
        TARGET_NAME="$1"
      else
        echo "Error: Multiple target names provided." >&2
        show_usage
        exit 1
      fi
      shift
      ;;
  esac
done

# Check if a target name was provided
if [ -z "$TARGET_NAME" ]; then
  echo "Error: No target name was provided." >&2
  show_usage
  exit 1
fi

# Validate platform
if [[ "$PLATFORM" != "macos" && "$PLATFORM" != "ios" ]]; then
  echo "Error: Platform must be either 'macos' or 'ios'." >&2
  show_usage
  exit 1
fi

# --- Main Execution ---

# 1. Construct the Prompt
# We store the instructions in a variable to pass to the -p flag.
# This separates the 'Instructions' from the 'Log Data' (stdin).

if [ "$PLATFORM" = "ios" ]; then
  PROMPT_TEXT="Below is the output of the \`xcodebuild build -scheme $TARGET_NAME -destination 'generic/platform=iOS' IPHONEOS_DEPLOYMENT_TARGET=16.0 -quiet\` command. It is too verbose and contains too much information. Please tell me what the compiler warnings are and then what the errors are. Give the error output exactly the same and then add a comment why it might be failing. We will use your output as logs. You will NOT work on these errors. We will take care of the rest."
else
  PROMPT_TEXT="Below is the output of the \`swift build --target $TARGET_NAME\` command. It is too verbose and contains too much information. Please tell me what the compiler warnings are and then what the errors are. Give the error output exactly the same and then add a comment why it might be failing. We will use your output as logs. You will NOT work on these errors. We will take care of the rest."
fi

# 2. Run Build and Pipe to Claude
# We redirect stderr to stdout (2>&1) so Claude sees both.

if [ "$PLATFORM" = "ios" ]; then
  defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
  
  # Pipe xcodebuild output into claude
  xcodebuild build -scheme "$TARGET_NAME" -destination 'generic/platform=iOS' IPHONEOS_DEPLOYMENT_TARGET=16.0 -quiet 2>&1 \
    | claude -p "$PROMPT_TEXT" --allowedTools "Read" --model haiku
    
  defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool NO
else
  # Pipe swift build output into claude
  swift build --target "$TARGET_NAME" 2>&1 \
    | claude -p "$PROMPT_TEXT" --allowedTools "Read" --model haiku
fi
