#!/usr/bin/env bats
#
# Test http:// downloads.
#

SUITE="http-dl"

load common

setup_file()
{
	BUILD_DATE="1970-01-01 01:01:01 +0000"

	#
	# XXX: pkgin does not (yet) print "marking <pkg> as non auto-removable"
	# messages when installing the first package to an empty pkgdb for some
	# reason, so just create a dummy package to act as the first one in
	# order to avoid changing the output matches.
	#
	create_pkg_buildinfo "preserve-1.0" \
	    "BUILD_DATE=${BUILD_DATE}" \
	    "CATEGORIES=download" \
	    "PKGPATH=download/preserve"
	create_pkg_comment "preserve-1.0" "Package should remain at all times"
	create_pkg_file "preserve-1.0" "share/doc/preserve"
	create_pkg_preserve "preserve-1.0"
	create_pkg "preserve-1.0"

	#
	# The packages are created normally, but our httpd knows to modify
	# the downloads inflight depending on the filename requested.  They
	# only differ on the COMMENT.
	#
	for pkg in ok notfound mismatch truncate; do
		create_pkg_buildinfo "download-${pkg}-1.0" \
		    "BUILD_DATE=${BUILD_DATE}" \
		    "CATEGORIES=download" \
		    "PKGPATH=download/download-${pkg}"
		case "${pkg}" in
		ok)	  c="Package tests download success" ;;
		notfound) c="Package tests download failure (404)" ;;
		mismatch) c="Package tests download failure (corrupt)" ;;
		truncate) c="Package tests incorrect pkgin cache" ;;
		esac
		create_pkg_comment "download-${pkg}-1.0" "${c}"
		create_pkg_file "download-${pkg}-1.0" \
		    "share/doc/download-${pkg}"
		create_pkg "download-${pkg}-1.0"
	done

	create_pkg_summary
	start_httpd

	rm -rf ${LOCALBASE} ${VARBASE}
	mkdir -p ${PKGIN_DBDIR}
}

teardown_file()
{
	stop_httpd
}

@test "${SUITE} perform initial pkgin setup" {
	#
	# Use pkg_add to aid pkgin-0.9 and also to keep the cache directory
	# empty.
	#
	export PKG_PATH=${PACKAGES}/All
	run pkg_add preserve
	[ ${status} -eq 0 ]

	run pkgin -fy update
	[ ${status} -eq 0 ]

	run rmdir ${PKGIN_CACHE}
	[ ${status} -eq 0 ]
}

#
# Test a successful file download.  Do not install.
#
@test "${SUITE} test download-only" {
	run pkgin -dy install download-ok
	[ ${status} -eq 0 ]
	if [ ${PKGIN_VERSION} -lt 001000 ]; then
		file_match "0.9" "download-only.regex"
	elif [ ${PKGIN_VERSION} -lt 001100 ]; then
		file_match "0.10" "download-only.regex"
	else
		file_match "download-only.regex"
	fi

	run [ -f ${PKGIN_CACHE}/download-ok-1.0.tgz ]
	[ ${status} -eq 0 ]

	run pkg_info -qe download-ok
	[ ${status} -eq 1 ]
}

#
# Now install separately.
#
@test "${SUITE} test install of already-downloaded package" {
	run pkgin -y install download-ok
	[ ${status} -eq 0 ]
	if [ ${PKGIN_VERSION} -lt 001000 ]; then
		file_match "0.9" "install-downloaded.regex"
	elif [ ${PKGIN_VERSION} -lt 001100 ]; then
		file_match "0.10" "install-downloaded.regex"
	elif [ ${PKGIN_VERSION} -eq 001600 ]; then
		# pkgin 0.16.0 is just broken with output differences
		:
	else
		file_match "install-downloaded.regex"
	fi

	run pkg_info -qe download-ok
	[ ${status} -eq 0 ]
}

#
# Test pkgin clean, should result in an empty directory that can successfully
# be rmdir'd.
#
@test "${SUITE} test pkgin clean" {
	run pkgin clean
	[ ${status} -eq 0 ]

	run rmdir ${PKGIN_CACHE}
	[ ${status} -eq 0 ]

	run [ ! -d ${PKGIN_CACHE} ]
	[ ${status} -eq 0 ]
}

#
# Now install to test both the install and also the download counters.
#
@test "${SUITE} test download and install" {
	run pkg_delete download-ok
	[ ${status} -eq 0 ]

	run pkgin -y install download-ok
	[ ${status} -eq 0 ]
	if [ ${PKGIN_VERSION} -lt 001000 ]; then
		file_match "0.9" "download-install.regex"
	elif [ ${PKGIN_VERSION} -lt 001100 ]; then
		file_match "0.10" "download-install.regex"
	elif [ ${PKGIN_VERSION} -eq 001600 ]; then
		# pkgin 0.16.0 is just broken with output differences
		:
	else
		file_match "download-install.regex"
	fi

	run pkg_info -qe download-ok
	[ ${status} -eq 0 ]
}

#
# These tests all rely on our fake httpd to amend the packages in transit
# even though they exist fine in the repository.
#
# pkgin-0.9.4 differs in some of the output, hence not supporting file_match
#
@test "${SUITE} test failed download (not found)" {
	run pkgin -y install download-notfound
	[ ${status} -eq 1 ]
	if [ ${PKGIN_VERSION} -lt 001000 ]; then
		file_match "0.9" "download-notfound.regex"
	elif [ ${PKGIN_VERSION} -lt 001100 ]; then
		file_match "0.10" "download-notfound.regex"
	elif [ ${PKGIN_VERSION} -eq 001600 ]; then
		# pkgin 0.16.0 is just broken with output differences
		:
	else
		file_match "download-notfound.regex"
	fi

	run [ -L ${PKGIN_CACHE}/download-notfound-1.0.tgz ]
	[ ${status} -eq 1 ]
}
@test "${SUITE} test failed download (truncated)" {
	run pkgin -y install download-truncate
	[ ${status} -eq 1 ]
	if [ ${PKGIN_VERSION} -lt 001000 ]; then
		file_match "0.9" "download-truncate.regex"
	elif [ ${PKGIN_VERSION} -lt 001100 ]; then
		file_match "0.10" "download-truncate.regex"
	elif [ ${PKGIN_VERSION} -eq 001600 ]; then
		# pkgin 0.16.0 is just broken with output differences
		:
	else
		file_match "download-truncate.regex"
	fi

	run [ -L ${PKGIN_CACHE}/download-truncate-1.0.tgz ]
	[ ${status} -eq 1 ]
}
@test "${SUITE} test failed download (mismatch)" {
	run pkgin -y install download-mismatch
	[ ${status} -eq 1 ]
	if [ ${PKGIN_VERSION} -lt 001000 ]; then
		file_match "0.9" "download-mismatch.regex"
	elif [ ${PKGIN_VERSION} -lt 001100 ]; then
		file_match "0.10" "download-mismatch.regex"
	elif [ ${PKGIN_VERSION} -eq 001600 ]; then
		# pkgin 0.16.0 is just broken with output differences
		:
	else
		file_match "download-mismatch.regex"
	fi

	run [ -L ${PKGIN_CACHE}/download-mismatch-1.0.tgz ]
	[ ${status} -eq 1 ]
}

#
# Test again but all at the same time to verify counters and output format.
#
@test "${SUITE} test all failed downloads" {
	run pkgin -y install download-notfound download-truncate \
			     download-mismatch
	[ ${status} -eq 1 ]
	if [ ${PKGIN_VERSION} -lt 001000 ]; then
		file_match "0.9" "download-all-failed.regex"
	elif [ ${PKGIN_VERSION} -lt 001100 ]; then
		file_match "0.10" "download-all-failed.regex"
	elif [ ${PKGIN_VERSION} -eq 001600 ]; then
		# pkgin 0.16.0 is just broken with output differences
		:
	else
		file_match "download-all-failed.regex"
	fi
}

# Verify everything is as it should be at the end of the tests.
@test "${SUITE} compare pkg_info" {
	compare_pkg_info "pkg_info.final"
}
