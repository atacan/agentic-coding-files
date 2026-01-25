#!/bin/bash

# This script builds a Swift target, captures its output and errors,
# prepends a detailed prompt, and pipes the result to the 'gemini' command for analysis.

# --- Configuration ---
# set -e: Exit immediately if a command exits with a non-zero status.
# set -u: Treat unset variables as an error.
# set -o pipefail: The pipeline's return code is the value of the last command to exit with a non-zero status.
# This is crucial for making the Makefile fail if 'swift build' fails.
set -euo pipefail

# --- Input Validation ---
# Function to show usage
show_usage() {
  echo "Usage: $0 [OPTIONS] <target-name>" >&2
  echo "Options:" >&2
  echo "  -p, --platform PLATFORM    Specify platform (macos|ios). Default: macos" >&2
  echo "  -h, --help                  Show this help message" >&2
  echo "" >&2
  echo "Examples:" >&2
  echo "  $0 MyTarget                 # Build for macOS using swift build" >&2
  echo "  $0 -p ios MyTarget          # Build for iOS using xcodebuild" >&2
  echo "  $0 --platform macos MyTarget # Build for macOS using swift build" >&2
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
# We group the prompt generation (cat) and the build command in a subshell (...).
# This allows us to redirect the standard output and standard error of BOTH commands
# into a single pipe to 'gemini'.

(
  # 1. Generate the prompt using a "Here Document" for maximum readability.
  # The content between <<EOF and EOF will be printed to standard output.
  if [ "$PLATFORM" = "ios" ]; then
    cat <<EOF
Below is the output of the \`xcodebuild build -scheme $TARGET_NAME -destination 'generic/platform=iOS' -quiet\` command.
It is too verbose and contains too much information. Please tell me what the compiler warnings are and then what the errors are.
Give the error output exactly the same and then add a comment why it might be failing.
We will use your output as logs. You will NOT work on these errors. We will take care of the rest.

EOF
  else
    cat <<EOF
Below is the output of the \`swift build --target $TARGET_NAME\` command.
It is too verbose and contains too much information. Please tell me what the compiler warnings are and then what the errors are.
Give the error output exactly the same and then add a comment why it might be failing.
We will use your output as logs. You will NOT work on these errors. We will take care of the rest.

EOF
  fi

  # 2. Run the actual build command. Its output (both stdout and stderr) will
  #    follow the prompt text from the Here Document.
  if [ "$PLATFORM" = "ios" ]; then
    defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
    xcodebuild build -scheme "$TARGET_NAME" -destination 'generic/platform=iOS' -quiet
    defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool NO
  else
    swift build --target "$TARGET_NAME"
  fi

# 3. Redirect stderr to stdout (2>&1) for the entire subshell group, then
#    pipe (|) the combined stream to the 'gemini' command.
) 2>&1 | DOTENV_CONFIG_DEBUG=false gemini
