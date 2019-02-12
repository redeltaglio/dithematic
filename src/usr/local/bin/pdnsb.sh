#!/bin/sh
# Backup PowerDNS SQLite

#set -eu
set -o errexit
set -o nounset

umask 077

# Bail out if non-privileged UID
[ 0 = "$(id -u)" ] || exit 1

KEY_DIR="${KEY_DIR:-/etc/pdns/dnssec}"
ZONE_DIR="${ZONE_DIR:-/var/nsd/zones/master}"
DB_DIR="${DB_DIR:-/var/pdns}"
PDNS_DB="pdns.sqlite pdnssec.sqlite"

[ -d ${KEY_DIR} ] || mkdir -p ${KEY_DIR}
[ -d ${ZONE_DIR} ] || mkdir -p ${ZONE_DIR}
[ -d ${DB_DIR} ] || mkdir -p ${DB_DIR}

# SQL to File
while read _zone
  do
    # Key ID
    local \
    _id=$(pdnsutil list-keys "${_zone}" | awk -v name="$_zone" '$0 ~ name { print $5 }')
    # Key format (i.e. CSK)
    local \
    _sk=$(pdnsutil list-keys "${_zone}" | awk -v name="$_zone" '$0 ~ name { print $2 }')
    # Export key
    if [ "${_id}" ]
      then
        # Private key
        pdnsutil export-zone-key "${_zone}" "${_id}" \
        > "${KEY_DIR}"/"${_zone}"."${_sk}"
        # DNSKEY RR
        pdnsutil export-zone-dnskey "${_zone}" "${_id}" \
        > "${KEY_DIR}"/"${_zone}".DNSKEY
      fi
    # Export zone
    # - remove last (SOA) RR
    # - add parenthesis to SOA RR
    # - remove DNSSEC RRSet
    drill -p 20053 AXFR "${_zone}" @localhost \
    | sed -e '$ d' -e '/SOA/ s/.*\. /& ( /' -e '/SOA/ s/$/ )/' -e '/NSEC3/d' -e '/RRSIG/d' -e '/DNSKEY/d' \
    > "${ZONE_DIR}"/"${_zone}".zone
  done << EOF
$(pdnsutil list-all-zones)
EOF

# SQL to SQL
rcctl stop pdns_server
for _db in ${PDNS_DB}
  do
    sqlite3 "${DB_DIR}"/"${_db}" .dump > "${DB_DIR}"/"${_db}".dump
    cp "${DB_DIR}"/"${_db}" "${DB_DIR}"/"${_db}".backup
  done
rcctl start pdns_server

