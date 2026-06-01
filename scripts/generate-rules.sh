#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
output_dir="${1:-publish}"

if [[ "${output_dir}" != /* ]]; then
  output_dir="${repo_root}/${output_dir}"
fi

CUSTOM_ICLOUD_URL="${CUSTOM_ICLOUD_URL:-https://raw.githubusercontent.com/Loyalsoldier/domain-list-custom/release/icloud.txt}"
CUSTOM_TLD_NOT_CN_URL="${CUSTOM_TLD_NOT_CN_URL:-https://raw.githubusercontent.com/Loyalsoldier/domain-list-custom/release/tld-!cn.txt}"
CUSTOM_PRIVATE_URL="${CUSTOM_PRIVATE_URL:-https://raw.githubusercontent.com/Loyalsoldier/domain-list-custom/release/private.txt}"
LOYALSOLDIER_REJECT_URL="${LOYALSOLDIER_REJECT_URL:-https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/reject-list.txt}"
LOYALSOLDIER_PROXY_URL="${LOYALSOLDIER_PROXY_URL:-https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/proxy-list.txt}"
LOYALSOLDIER_DIRECT_URL="${LOYALSOLDIER_DIRECT_URL:-https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/direct-list.txt}"
LOYALSOLDIER_GFW_URL="${LOYALSOLDIER_GFW_URL:-https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/gfw.txt}"
LOYALSOLDIER_GREATFIRE_URL="${LOYALSOLDIER_GREATFIRE_URL:-https://raw.githubusercontent.com/Loyalsoldier/v2ray-rules-dat/release/greatfire.txt}"
FELIXONMARS_APPLE_URL="${FELIXONMARS_APPLE_URL:-https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/apple.china.conf}"
FELIXONMARS_GOOGLE_URL="${FELIXONMARS_GOOGLE_URL:-https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/google.china.conf}"
CN_CIDR_URL="${CN_CIDR_URL:-https://raw.githubusercontent.com/Loyalsoldier/geoip/release/text/cn.txt}"
LAN_CIDR_URL="${LAN_CIDR_URL:-https://raw.githubusercontent.com/Loyalsoldier/geoip/release/text/private.txt}"
TELEGRAM_CIDR_URL="${TELEGRAM_CIDR_URL:-https://raw.githubusercontent.com/Loyalsoldier/geoip/release/text/telegram.txt}"
APPLICATIONS_FILE="${APPLICATIONS_FILE:-rules/applications.txt}"

DOMAIN_RE='^[-_[:alnum:]]+(\.[-_[:alnum:]]+)*$'

fetch() {
  curl --fail --location --silent --show-error --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 60 "$1"
}

write_payload() {
  printf 'payload:\n' > "$1"
}

generate_icloud() {
  write_payload icloud.txt
  fetch "${CUSTOM_ICLOUD_URL}" | awk -F: -v domain_re="${DOMAIN_RE}" '
    { sub(/\r$/, "") }
    /^(full|domain):/ && $2 ~ domain_re { printf "  - \047+.%s\047\n", $2 }
  ' >> icloud.txt
}

generate_dnsmasq_domains() {
  local url="$1"
  local target="$2"

  write_payload "${target}"
  fetch "${url}" | awk -F/ '
    { sub(/\r$/, "") }
    $1 == "server=" && $2 != "" { printf "  - \047+.%s\047\n", $2 }
  ' >> "${target}"
}

generate_private() {
  write_payload private.txt
  fetch "${CUSTOM_PRIVATE_URL}" | awk -F: -v domain_re="${DOMAIN_RE}" '
    { sub(/\r$/, "") }
    /^full:/ && $2 ~ domain_re { printf "  - \047%s\047\n", $2; next }
    /^domain:/ && $2 ~ domain_re { printf "  - \047+.%s\047\n", $2 }
  ' >> private.txt
}

generate_domain_rules() {
  local url="$1"
  local target="$2"

  write_payload "${target}"
  fetch "${url}" | awk -F: -v domain_re="${DOMAIN_RE}" '
    { sub(/\r$/, "") }
    /^(regexp|keyword):/ { next }
    /^full:/ && $2 ~ domain_re { printf "  - \047%s\047\n", $2; next }
    /^domain:/ && $2 ~ domain_re { printf "  - \047+.%s\047\n", $2; next }
    $0 !~ /:/ && $0 ~ domain_re { printf "  - \047+.%s\047\n", $0 }
  ' >> "${target}"
}

generate_domain_suffix_rules() {
  local url="$1"
  local target="$2"

  write_payload "${target}"
  fetch "${url}" | awk -F: -v domain_re="${DOMAIN_RE}" '
    { sub(/\r$/, "") }
    /^(regexp|keyword):/ { next }
    /^(domain|full):/ && $2 ~ domain_re { printf "  - \047+.%s\047\n", $2; next }
    $0 !~ /:/ && $0 ~ domain_re { printf "  - \047+.%s\047\n", $0 }
  ' >> "${target}"
}

generate_tld_not_cn() {
  write_payload tld-not-cn.txt
  fetch "${CUSTOM_TLD_NOT_CN_URL}" | awk -F: -v domain_re="${DOMAIN_RE}" '
    { sub(/\r$/, "") }
    /^domain:/ && $2 ~ domain_re { printf "  - \047+.%s\047\n", $2 }
  ' >> tld-not-cn.txt
}

generate_cidr_rules() {
  local url="$1"
  local target="$2"

  write_payload "${target}"
  fetch "${url}" | awk '
    { sub(/\r$/, "") }
    /^[0-9A-Fa-f:.]+\/[0-9]+$/ { printf "  - \047%s\047\n", $0 }
  ' >> "${target}"
}

copy_applications() {
  local source="${APPLICATIONS_FILE}"

  if [[ "${source}" != /* ]]; then
    source="${repo_root}/${source}"
  fi

  if [[ ! -f "${source}" ]]; then
    printf 'Missing applications file: %s\n' "${source}" >&2
    exit 1
  fi

  cp "${source}" applications.txt
}

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

output_files=(
  icloud.txt
  google.txt
  apple.txt
  private.txt
  direct.txt
  proxy.txt
  reject.txt
  gfw.txt
  greatfire.txt
  tld-not-cn.txt
  cncidr.txt
  telegramcidr.txt
  lancidr.txt
  applications.txt
)

mkdir -p "${output_dir}"
for file in "${output_files[@]}"; do
  rm -f "${output_dir}/${file}"
done

cd "${work_dir}"
generate_icloud
generate_dnsmasq_domains "${FELIXONMARS_GOOGLE_URL}" google.txt
generate_dnsmasq_domains "${FELIXONMARS_APPLE_URL}" apple.txt
generate_private
generate_domain_rules "${LOYALSOLDIER_DIRECT_URL}" direct.txt
generate_domain_rules "${LOYALSOLDIER_PROXY_URL}" proxy.txt
generate_domain_suffix_rules "${LOYALSOLDIER_REJECT_URL}" reject.txt
generate_domain_suffix_rules "${LOYALSOLDIER_GFW_URL}" gfw.txt
generate_domain_suffix_rules "${LOYALSOLDIER_GREATFIRE_URL}" greatfire.txt
generate_tld_not_cn
generate_cidr_rules "${CN_CIDR_URL}" cncidr.txt
generate_cidr_rules "${TELEGRAM_CIDR_URL}" telegramcidr.txt
generate_cidr_rules "${LAN_CIDR_URL}" lancidr.txt
copy_applications

for file in "${output_files[@]}"; do
  cp "${file}" "${output_dir}/"
done
printf 'Generated rule files in %s\n' "${output_dir}"
