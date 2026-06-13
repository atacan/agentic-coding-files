#!/bin/bash

# This script builds a Swift target, captures its output and errors,
# and pipes the result to an AI command for analysis.

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
IOS_DEPLOYMENT_TARGET="17.0"

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
  PROMPT_TEXT="Below is the output of the \`xcodebuild build -scheme $TARGET_NAME -destination 'generic/platform=iOS' IPHONEOS_DEPLOYMENT_TARGET=$IOS_DEPLOYMENT_TARGET -quiet\` command. It is too verbose and contains too much information. Please tell me what the compiler warnings are and then what the errors are. Give the error output exactly the same and then add a comment why it might be failing. We will use your output as logs. You will NOT work on these errors. We will take care of the rest."
else
  PROMPT_TEXT="Below is the output of the \`swift build --target $TARGET_NAME\` command. It is too verbose and contains too much information. Please tell me what the compiler warnings are and then what the errors are. Give the error output exactly the same and then add a comment why it might be failing. We will use your output as logs. You will NOT work on these errors. We will take care of the rest."
fi

# 2. Function to analyze build output with AI tools (fallback chain)
analyze_with_ai() {
  local build_output="$1"

  # Try codex first. Use `exec` because `codex -p` is `--profile`, not a prompt flag.
  if command -v codex &> /dev/null; then
    echo "Analyzing with codex..." >&2
    local codex_output_file
    if codex_output_file=$(mktemp); then
      if printf '%s\n' "$build_output" | codex -c 'model_reasoning_effort="low"' --sandbox read-only -a never exec -o "$codex_output_file" "$PROMPT_TEXT" >/dev/null 2>/dev/null; then
        cat "$codex_output_file"
        rm -f "$codex_output_file"
        return 0
      fi
      rm -f "$codex_output_file"
    else
      echo "Could not create temporary output file for codex." >&2
    fi

    if printf '%s\n' "$build_output" | codex -c 'model_reasoning_effort="low"' --sandbox read-only -a never exec "$PROMPT_TEXT" 2>/dev/null; then
      return 0
    fi
    echo "codex failed, trying claude..." >&2
  fi

  # Try claude second
  if command -v claude &> /dev/null; then
    echo "Analyzing with claude..." >&2
    if printf '%s\n' "$build_output" | claude -p "$PROMPT_TEXT" --allowedTools "Read" --model haiku 2>/dev/null; then
      return 0
    fi
    echo "claude failed, trying gemini..." >&2
  fi
  
  # Try gemini third
  if command -v gemini &> /dev/null; then
    echo "Analyzing with gemini..." >&2
    if printf '%s\n' "$build_output" | gemini -p "$PROMPT_TEXT" 2>/dev/null; then
      return 0
    fi
    echo "gemini failed." >&2
  fi
  
  # All tools failed, output raw build output
  echo "All AI tools failed. Raw build output:" >&2
  echo "$build_output"
  return 1
}

# 3. Run Build and Analyze with AI (fallback chain)
if [ "$PLATFORM" = "ios" ]; then
  defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
  
  # Capture xcodebuild output
  BUILD_OUTPUT=$(xcodebuild build -scheme "$TARGET_NAME" -destination 'generic/platform=iOS' IPHONEOS_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET" -quiet 2>&1 || true)
  
  defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool NO
  
  # Analyze with AI fallback chain
  analyze_with_ai "$BUILD_OUTPUT"
else
  # Capture swift build output
  BUILD_OUTPUT=$(swift build --target "$TARGET_NAME" 2>&1 || true)
  
  # Analyze with AI fallback chain
  analyze_with_ai "$BUILD_OUTPUT"
fi
