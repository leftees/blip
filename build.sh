#!/bin/bash
#
# MIT License
#
# Copyright (c) 2016 Nicola Worthington
#

set -ueo pipefail
declare -g verbose; [[ ! $- =~ [vx] ]]; verbose=${?//0/}
shopt -s checkwinsize
umask 0077

_mark () {
  declare msg="${1:-}"
  declare colour="${2:-yellow}"
  declare width=${COLUMNS:-80}
  declare len=$(( width - ${#msg} ))
  if [[ $len -lt $width ]] ; then
    len=$(( len - 4 ))
  fi
  echo -n "${ANSI[bold]}${ANSI[$colour]}"
  printf "=%.0s" {1..5}
  echo -n "${msg:+[ $msg ]}"
  printf "=%.0s" $(seq 1 $(( len - 5 )))
  echo "${ANSI[reset]}"
}

_prepare_gpg_signing () {
  _mark "_prepare_gpg_signing()" "green"
  gpg_keyid="6393F646"
  debuild_extra_args="-k${gpg_keyid} -S"
  rpmbuild_extra_args="--sign"
  while read -r line ; do
    if ! grep -q "^$line$" ~/.rpmmacros ; then
      echo "$line" >> ~/.rpmmacros
    fi
  done <<RPMMACROS
%_signature gpg
%_gpg_name $(get_gecos_name)
%_gpgbin /usr/bin/gpg
RPMMACROS
}

_render_documentation () {
  _mark "_render_documentation()" "green"
  pod2man \
    --name="BLIP.BASH" \
    --release="${pkg}.bash $version" \
    --center="${pkg}.bash" \
    --section=3 \
    --utf8 "$base/${pkg}.bash.pod" > "$base/${pkg}.bash.3"
  if is_in_path "markdown" ; then
    markdown "$base/README.md"
  else
    echo "Missing 'markdown' package is required to build README.html from README.md."
  fi > "$base/README.html"
}

_build_deb_packages () {
  _mark "_build_deb_packages()" "magenta"
  _debuild () {
    _mark "_debuild()" "magenta"
    declare release_dir="$1"
    declare debuild_extra_args="${2:-}"
    declare debian_orig_tar="${release_tarball%.tar.gz}.orig.tar.gz"
    debian_orig_tar="${debian_orig_tar//-/_}"

    # TODO(nicolaw): Update the debian/changelog from git log output.
    pushd "$build_dir"
    cp ${verbose:+-v} "$release_tarball" "$debian_orig_tar"
    debuild -sa ${debuild_extra_args:- -us -uc}
    mkdir -p ${verbose:+-v} "$release_dir"
    mv ${verbose:+-v} -- "$build_base"/*.{dsc,changes,build,debian.tar.gz,orig.tar.gz} "$release_dir"
    popd

    if stat -t "$build_base"/*.deb >/dev/null 2>&1 ; then
      mv ${verbose:+-v} -- "$build_base"/*.deb "$release_dir"
      _mark "DEB Package Information"
      dpkg-deb -I "$release_dir/${pkg}_${version}${release:+-$release}_all.deb"
      dpkg-deb -c "$release_dir/${pkg}_${version}${release:+-$release}_all.deb"
      _mark
    fi
  }

  _debuild "$release_dir"
  [[ -n "$debuild_extra_args" ]] && _debuild "$release_dir/deb-src" "$debuild_extra_args"
}

_build_rpm_packages () {
  _mark "_build_rpm_packages()" "magenta"
  # TODO(nicolaw): Update the %changelog from git log output.
  rpmbuild -ba "$base/${pkg}.spec" \
    ${rpmbuild_extra_args} \
    ${pkg:+--define "name $pkg"} \
    ${version:+--define "version $version"} \
    ${release:+--define "release $release"} \
    --define "_sourcedir $build_base" \
    --define "_rpmdir $release_dir" \
    --define "_build_name_fmt %%{NAME}-%%{VERSION}-%%{RELEASE}.%%{ARCH}.rpm"
  _mark "RPM Package Information"
  rpm -qlpi ${verbose:+-v} "$release_dir/${pkg}-${version}${release:+-$release}.noarch.rpm"
  _mark
}

_build_tarball () {
  _mark "_build_tarball()" "magenta"
  rm -Rf ${verbose:+-v} --one-file-system --preserve-root "$build_base"
  mkdir -p ${verbose:+-v} "$build_dir" "$release_dir"
  rsync -a ${verbose:+-v} --exclude=".*" --exclude="build/" --exclude="release/" "${base%/}/" "${build_dir%}/"
  tar -C "$build_base" ${verbose:+-v} -zcf "$release_tarball" "${build_dir##*/}/"
  cp ${verbose:+-v} "$release_tarball" "$release_dir"
}

main () {
  declare base
  base="$(readlink -f "${BASH_SOURCE[0]%/*}")"
  declare pkg="blip"

  [[ -e "$base/${pkg}.bash" ]]
  # shellcheck disable=SC2034
  BLIP_ANSI_VARIABLES=true
  source "$base/${pkg}.bash"

  # git tag -u 6393F646 -a v0.3-1 -m 'Initial successful LaunchPad PPA submission' 7947d41
  # git config --global user.signingkey "6393F646"
  # git --no-pager log v0.3-1..HEAD --pretty --format='%cD,%cn,%ce,%h,"%s","%d"'
  # git --no-pager log  --pretty --format='%cD,%cn,%ce,%h,"%s","%d"'
  # git tag -l -n9
  # git tag -l 

  # TODO(nicolaw): Pull version information from the current git tag.
  #                A git tag of HEAD should be regarded as UNRELEASED.
  declare dch_version_full
  dch_version_full="$(egrep -o "^${pkg} \([0-9]+\.[0-9]+(-[0-9]+)?\) " "$base/debian/changelog" | egrep -o '[0-9]+\.[0-9]+(-[0-9]+)?' | head -1)"
  declare dch_version="${dch_version_full%-*}"
  declare dch_release="${dch_version_full#*-}"
  declare version="${1:-$dch_version}"
  declare release="${2:-$dch_release}"
  release="${release:-1}"

  [[ "$version" =~ ^[0-9]+\.[0-9]+$ ]]
  is_abs_int "$release"

  # Declare build and release paths.
  declare build_base="$base/build"
  declare build_dir="$build_base/${pkg}-${version}"
  declare release_dir="$base/release/${pkg}-${version}${release:+-$release}"
  declare release_tarball="$build_base/${pkg}-${version}.tar.gz"

  # Sign with the authors key.
  declare rpmbuild_extra_args
  declare debuild_extra_args
  declare gpg_keyid
  if [[ "$(hostid)" = "007f0101" ]] && [[ "$(get_username)" = "nicolaw" ]] ; then
    _prepare_gpg_signing
  fi

  # Generate some Groff man pages from the POD source.
  _render_documentation

  # Build tarball.
  _build_tarball

  # Build Deb package.
  if is_in_path "debuild" "dpkg-deb" ; then
    _build_deb_packages
  fi

  # Build RPM package.
  if is_in_path "rpmbuild" "rpm" ; then
    _build_rpm_packages
  fi

  # List the resulting release package files.
  ls --color -Rla "$release_dir"
}

main "$@"

