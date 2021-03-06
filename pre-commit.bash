#!/usr/bin/env bash
# shellcheck disable=SC2034
# Comments prefixed by BASHDOC: are hints to specific GNU Bash Manual's section:
# https://www.gnu.org/software/bash/manual/

## Makes debuggers' life easier - Unofficial Bash Strict Mode
## http://redsymbol.net/articles/unofficial-bash-strict-mode/
## BASHDOC: Shell Builtin Commands - Modifying Shell Behavior - The Set Builtin
### Exit prematurely if a command's return value is not 0(with some exceptions), triggers ERR trap if available.
set -o errexit

### Trap on `ERR' is inherited by shell functions, command substitutions, and subshell environment as well
set -o errtrace

### Exit prematurely if an unset variable is expanded, causing parameter expansion failure.
set -o nounset

### Let the return value of a pipeline be the value of the last (rightmost) command to exit with a non-zero status
set -o pipefail

## Non-overridable Primitive Variables
##
## BashFAQ/How do I determine the location of my script? I want to read some config files from the same place. - Greg's Wiki
## http://mywiki.wooledge.org/BashFAQ/028
RUNTIME_EXECUTABLE_FILENAME="$(basename "${BASH_SOURCE[0]}")"
declare -r RUNTIME_EXECUTABLE_FILENAME
declare -r RUNTIME_EXECUTABLE_NAME="${RUNTIME_EXECUTABLE_FILENAME%.*}"
RUNTIME_EXECUTABLE_DIRECTORY="$(dirname "$(realpath "${0}")")"
declare -r RUNTIME_EXECUTABLE_DIRECTORY
declare -r RUNTIME_EXECUTABLE_PATH_ABSOLUTE="${RUNTIME_EXECUTABLE_DIRECTORY}/${RUNTIME_EXECUTABLE_FILENAME}"
declare -r RUNTIME_EXECUTABLE_PATH_RELATIVE="${0}"
declare -r RUNTIME_COMMAND_BASE="${RUNTIME_COMMAND_BASE:-${0}}"

declare global_temp_directory

## init function: program entrypoint
init(){
	# Simple definition file, don't bother
	# shellcheck source=/dev/null
	source "${RUNTIME_EXECUTABLE_DIRECTORY}/APPLICATION_METADATA.source"

	check_runtime_dependencies

	if ! create_temp_directory; then
		printf 'Error: Unable to create temporary directory.\n' 1>&2
		exit 1
	fi

	# Checkout all scripts from staging area to temp folder
	# False positive of SC2026
	# shellcheck disable=SC2026
	git diff -z --cached --name-only --diff-filter=ACM '*.bash'\
		| git checkout-index --stdin -z --prefix="${global_temp_directory}/"

	# Run ShellCheck on all scripts
	declare check_result='UNKNOWN';

	# Change to staging dir so that we can only show relative path to the script instead of long ugly path including tmpdir path
	pushd "${global_temp_directory}" >/dev/null

	# delimiter - bash "for in" looping on null delimited string variable - Stack Overflow
	# http://stackoverflow.com/questions/8677546/bash-for-in-looping-on-null-delimited-string-variable
	# False positive
	# shellcheck disable=SC2026
	while IFS='' read -r -d '' file; do
		printf -- \
			'%s: Checking %s...\n' \
			"${META_APPLICATION_NAME}" \
			"${file}"
		if ! shellcheck --shell=bash "${file}"; then
			check_result='FAILED'
		fi
		done < <(
		find \
			. \
			-name '*.bash' \
			-type f \
			-print0
	) # this is a process substitution

	popd >/dev/null

	if [ "${check_result}" == 'FAILED' ]; then
		printf -- \
			'%s: ERROR: ShellCheck failed, please check your script.\n' \
			"${META_APPLICATION_NAME}" \
			1>&2
		exit 1
	fi
	printf -- \
		'%s: ShellCheck succeeded.\n' \
		"${META_APPLICATION_NAME}"
	exit 0
}; declare -fr init

create_temp_directory(){
	if ! global_temp_directory="$(mktemp --directory --tmpdir "${RUNTIME_EXECUTABLE_NAME}".XXXXXX.tmpdir)"; then
		return 1
	fi
	return 0
}
readonly -f create_temp_directory

cleanUpBeforeNormalExit(){
	# If temp directory isn't created yet, don't bother
	if test -v global_temp_directory; then
		rm -rf "${global_temp_directory}"\
			|| printf "%s: Error: Failed to remove temp directory" "${RUNTIME_EXECUTABLE_NAME}" 1>&2
	fi
	return 0
}
declare -fr cleanUpBeforeNormalExit

trap_errexit(){
	printf 'An error occurred and the script is prematurely aborted\n' 1>&2
	return 0
}; declare -fr trap_errexit; trap trap_errexit ERR

trap_exit(){
	cleanUpBeforeNormalExit
	return 0
}; declare -fr trap_exit; trap trap_exit EXIT

check_runtime_dependencies(){
	for a_command in shellcheck rm find; do
		if ! command -v "${a_command}" &>/dev/null; then
			printf '%s: %s: Error: Command %s not found, please check your runtime dependencies.\n' \
				"${RUNTIME_EXECUTABLE_NAME}" "${FUNCNAME[0]}" "${a_command}" 1>&2
			exit 1
		fi
	done
}; declare -fr check_runtime_dependencies

init "${@}"

## This script is based on the GNU Bash Shell Script Template project
## https://github.com/Lin-Buo-Ren/GNU-Bash-Shell-Script-Template
## and is based on the following version:
## META_BASED_ON_GNU_BASH_SHELL_SCRIPT_TEMPLATE_VERSION="v1.24.1"
## You may rebase your script to incorporate new features and fixes from the template
