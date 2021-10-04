#!/bin/sh

# This script will install buildah using the automated builds from the kubic
# project

set -eu

# Default directories for user data and binaries (according to XDG)
XDG_DATA_HOME=${XDG_DATA_HOME:-${HOME%/}/.local/share}
XDG_BIN_HOME=${XDG_BIN_HOME:-${HOME%/}/.local/bin}

# Local directory to use when installing in local user.
PWSH_LOCAL=${PWSH_LOCAL:-${XDG_DATA_HOME}/opt/microsoft/powershell}

# Set this to 1 for more verbosity (on stderr)
PWSH_VERBOSE=${PWSH_VERBOSE:-0}

# Powershell version to download (from GitHub), empty (the default) means latest
# stable as of the official powershell releases.
PWSH_VERSION=${PWSH_VERSION:-}

# Root URL where the powershell packages are available, per distribution.
PWSH_ROOT=${PWSH_ROOT:-https://packages.microsoft.com/}

# Organisation and name of powershell project at GitHub.
PWSH_GHPROJ=${PWSH_GHPROJ:-PowerShell/PowerShell}

# Root URL for powershell releases at GitHub
PWSH_GHROOT=${PWSH_GHROOT:-https://github.com/${PWSH_GHPROJ}/releases/download}

# Root URL for API calls for the powershell project at GitHub. Mind you: rate
# limited without auth, but we only make one call!
PWSH_GHAPI=${PWSH_GHAPI:-https://api.github.com/repos/${PWSH_GHPROJ}}

# Rootname of the RPM and DEB packages under the hierarchy of PWSH_ROOT
PWSH_PKGNAME=${PWSH_PKGNAME:-packages-microsoft-prod}

# Local repositories roots, per distribution
PWSH_APTROOT=${PWSH_APTROOT:-"/etc/apt/sources.list.d"}
PWSH_YUMROOT=${PWSH_YUMROOT:-"/etc/yum.repos.d"}

# This uses the comments behind the options to show the help. Not extremly
# correct, but effective and simple.
usage() {
  echo "$0 installs powershell from the official Microsoft packages:" && \
    head -n 100 "$0" | grep "[[:space:]].)\ #" |
    sed 's/#//' |
    sed -r 's/([a-z])\)/-\1/'
  exit "${1:-0}"
}

while getopts "r:l:vh-" opt; do
  case "$opt" in
    r) # Release version to download when using GH releases, empty for latest (default)
      PWSH_VERSION=$OPTARG;;
    l) # Local directory to install to when doing non-root installations, empty for XDG-based.
      PWSH_LOCAL=$OPTARG;;
    v) # Turn on verbosity
      PWSH_VERBOSE=1;;
    h) # Print help and exit
      usage;;
    -)
      break;;
    *)
      usage 1;;
  esac
done
shift $((OPTIND-1))

# TODO: We need to reason better around the wget installation code. When root,
# we are able to install the relevant packages, so we should kickstat
# installation of curl/wget if none can be found.


_logline() {
  printf '[%s] [%s] %s\n' "$(basename "$0")" "${2:-NFO}" "$1" >&2
}

_verbose() {
  if [ "$PWSH_VERBOSE" = "1" ]; then
    _logline "$1"
  fi
}

_warn() {
  _logline "$1" "WRN"
}

_error() {
  _logline "$1" "ERR"
  exit 1
}

# Download the URL passed as a parameter, not output on the console, follow all
# redirects. This will use curl or wget, depending on which one is installed.
_download() {
  _verbose "Downloading $1"
  if command -v curl >/dev/null 2>&1; then
    curl -sSL "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O - "$1"
  else
    _error "Can neither find curl, nor wget for downloading"
  fi
}


# This isn't used. It is trying to follow the instructions at
# https://docs.microsoft.com/en-us/powershell/scripting/install/install-fedora?view=powershell-7.1#installation-via-package-repository,
# but they do not seem to work.
_rpm() {
  _verbose "Importing Microsoft signature key"
  rpm --import "${PWSH_ROOT%/}/keys/microsoft.asc"
  _verbose "Register YUM repository"
  _download "$1" > "${PWSH_YUMROOT%/}/microsoft.repo"
  dnf check-update || true
  _verbose "Install dependencies and powershell"
  yum install -y compat-openssl10
  yum install -y powershell
}

# Guess latest stable release version of powershell made at GitHub.
_version() {
  if [ -z "$PWSH_VERSION" ]; then
    PWSH_VERSION=$( _download "${PWSH_GHAPI%/}/releases" |
                    grep -oE "[[:space:]]*\"tag_name\"[[:space:]]*:[[:space:]]*\"v([0-9]+\.[0-9]+\.[0-9]+)\"" |
                    sed -E "s/[[:space:]]*\"tag_name\"[[:space:]]*:[[:space:]]*\"v([0-9]+\.[0-9]+\.[0-9]+)\"/\\1/" |
                    head -n 1 )
    _verbose "Latest stable powershell release: $PWSH_VERSION"
  fi
}

# Install from YUM package pointed at URL passed as an argument
_yum() {
  _verbose "Trying optional dependencies"
  yum install -y compat-openssl10 || true
  _verbose "Installing package from: $1"
  yum install -y "$1"
}

# Install from DEB package pointed at URL passed as an argument. This will
# ensure that there is a wget to download stuff.
_deb() {
  # shellcheck disable=SC3043 # local implemented almost everywhere
  local _rm || true

  # Make sure we have at least wget installed, remember the package in _rm so we
  # can remove if necessary once done.
  if ! command -v wget >&2 >/dev/null; then
    _verbose "Temporarily installing binary dependencies"
    apt-get update -qq
    apt-get -qq -y install wget
    _rm=wget
  fi

  _verbose "Installing powershell using deb package from $1"
  _download "$1" > "/tmp/${PWSH_PKGNAME}.deb"
  dpkg -i "/tmp/${PWSH_PKGNAME}.deb"
  apt-get update -y -qq
  apt-get install -y -q powershell
  rm -f "/tmp/${PWSH_PKGNAME}.deb"

  # Cleanup temporary packages, i.e. wget (but following code is generic!)
  if [ -n "${_rm:-}" ]; then
    _verbose "Cleaning away temporary dependencies"
    apt-get remove -y $_rm
    apt-get auto-remove -y
  fi
  apt-get clean
}

install_asroot() {
  # Discover distribution
  if [ -f "/etc/os-release" ]; then
    # shellcheck disable=SC1091  # Path and variables are standardised!
    . /etc/os-release
  else
    _error "Cannot find OS release information at /etc/os-release"
  fi

  case "$ID" in
    ubuntu | debian)
      _deb "${PWSH_ROOT%/}/config/${ID}/${VERSION_ID}/${PWSH_PKGNAME}.deb"
      ;;
    fedora)
      _version
      _yum "${PWSH_GHROOT%/}/v${PWSH_VERSION}/powershell-${PWSH_VERSION}-1.rhel.7.$(uname -i).rpm"
      ;;
    centos)
      _version
      if [ "$VERSION" = "8" ]; then
        _yum "${PWSH_GHROOT%/}/v${PWSH_VERSION}/powershell-${PWSH_VERSION}-1.centos.${VERSION}.$(uname -i).rpm"
      else
        _yum "${PWSH_GHROOT%/}/v${PWSH_VERSION}/powershell-${PWSH_VERSION}-1.rhel.${VERSION}.$(uname -i).rpm"
      fi
      ;;
    *)
      _error "Don't know how to install for $NAME"
      ;;
  esac
}

# Guess machine architecture in a way that is compatible with the PowerShell
# release URLs at GitHub.
_arch() {
  case "$(uname -m)" in
    x86_64) echo "x64";;
    armv7*) echo "arm32";;
    armv8*) echo "arm64";;
    aarch64) echo "arm64";;
    *) _error "Unknown machine architecture";;
  esac
}

install_asuser() {
  # shellcheck disable=SC3043 # local implemented almost everywhere
  local _tmpd || true

  _version
  _tmpd=$(mktemp -d)

  _download "${PWSH_GHROOT%/}/v${PWSH_VERSION}/powershell-${PWSH_VERSION}-$(uname -s | tr '[:upper:]' '[:lower:]')-$(_arch).tar.gz" > "${_tmpd}/pwsh.tgz"
  mkdir -p "$PWSH_LOCAL"
  _verbose "Installing PowerShell v$PWSH_VERSION into $PWSH_LOCAL"
  tar -C "$PWSH_LOCAL" -xf "${_tmpd}/pwsh.tgz"
  rm -rf "${_tmpd}"
  if [ -f "${PWSH_LOCAL}/pwsh" ]; then
    if [ -d "$XDG_BIN_HOME" ]; then
      _verbose "Making pwsh accessible from $XDG_BIN_HOME"
      ln -s "${PWSH_LOCAL}/pwsh" "${XDG_BIN_HOME%/}/pwsh"
      if ! printf %s\\n "$PATH" | grep -q "${XDG_BIN_HOME%/}"; then
        export PATH="${XDG_BIN_HOME%/}:$PATH"
      fi
      if [ -n "${GITHUB_PATH:-}" ]; then
        echo "${XDG_BIN_HOME%/}" >> "$GITHUB_PATH"
      fi
    else
      _verbose "Making pwsh accessible from $PWSH_LOCAL"
      export PATH="${PWSH_LOCAL%/}:$PATH"
      if [ -n "${GITHUB_PATH:-}" ]; then
        echo "${PWSH_LOCAL%/}" >> "$GITHUB_PATH"
      fi
    fi
    if ! pwsh --version >/dev/null 2>&1; then
      if pwsh --version 2>&1 | grep -q ICU; then
        _warn "Disabling pwsh globalisation support"
        if [ -n "${GITHUB_ENV:-}" ]; then
          echo "DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1" >> "$GITHUB_PATH"
        fi
        export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
      else
        _error "Could not install working pwsh"
      fi
    fi
  else
    _error "Could not install powershell to $PWSH_LOCAL"
  fi
}


if ! command -v pwsh >/dev/null 2>&1; then
  if [ "$(id -u)" = "0" ]; then
    install_asroot
  else
    install_asuser
  fi
fi

# Run powershell, printing out the version. If installation failed without a
# proper failure, this would arrange to fail. Knowing the installed version is
# also a good piece of information.
pwsh --version
