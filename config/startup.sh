#!/bin/bash
#set d -e

# Ensure restart trigger directory exists
mkdir -p /var/run/restart-trigger

# ── Band frequency plan (single source of truth) ──────────────────────────────
# These drive both the SkimSrv .ini files and the tuning-range check below, so
# the centre frequencies are defined exactly once.
#
# 6m notes: the CW-only allocation is 50.000-50.100 MHz in all three IARU
# regions (50.060-50.080 is the Region 2 beacon sub-band, 50.090 the CW DX
# calling frequency). The IARU Region 1 beacon band is separate, at
# 50.400-50.500 MHz, and gets its own centre frequency / BAND_6M_BEACONS flag.
#
# SkimSrv does not use the whole sampled bandwidth: the usable passband is
# +/-45.5 kHz at 96 kHz (91 of 96) and +/-91 kHz at 192 kHz (182 of 192), the
# remainder being guard band. It also displays the BOTTOM of that passband as
# the dial frequency, not the centre — which is why every entry here is
# 'segment start + 45500' (or + 91000), so each band reads as a round number.
#
#   96 kHz : idx 12 = 50.0545 MHz (CW, covers 50.009-50.100, reads 50.009.0)
#            idx 13 = 50.4455 MHz (R1 beacons, covers 50.400-50.491, reads 50.400.0)
#   192 kHz: idx 11 = 50.091  MHz (CW, covers 50.000-50.182, reads 50.000.0)
#            idx 12 = 50.491  MHz (R1 beacons, covers 50.400-50.582, reads 50.400.0)
#
# At 192 kHz both 6m segments fit whole. At 96 kHz a 100 kHz segment does not
# fit in a 91 kHz passband, so 9 kHz must be given up: for CW we drop
# 50.000-50.009, dead band-edge space, which keeps the 50.060-50.080 Region 2
# beacon sub-band and the 50.090 CW DX calling frequency well inside the
# passband rather than against its roll-off. For the beacon band we drop the
# top 9 kHz, keeping the busier lower half and a round dial reading.
#
# Note the tuning-range gate below still tests centre +/- SAMPLE_RATE/2, not
# the usable half-width: the SDR has to deliver the full sampled window.
CENTER_FREQS_48="1822750,3522750,3568250,7022750,10122750,14022750,14068250,18090750,21022750,21068250,24912750,28022750,28068250,50022750,50068250,50113750,50159250"
CENTER_FREQS_96="1845500,3545500,5306500,7045500,10145500,14045500,18113500,21045500,24935500,28045500,28136500,28225000,50054500,50445500,14100000,21150000"
CENTER_FREQS_192="1891000,3591000,5355000,7091000,10191000,14091000,18159000,21091000,24981000,28091000,28225000,50091000,50491000"
# The whole-plan segment list: 14 entries, used for the .ini templates and as a
# fallback for an instance that has no bands. Do not grow it - SkimSrv has a
# ceiling here, and pushing this list to 16 entries made every instance spin up
# zero decoders, on all bands, not just the added ones. Each instance gets a
# list built from its own bands instead (see build_segment_list).
CW_SEGMENTS="1800000-1840000,3500000-3570000,5258500-5358000,7000000-7035000,7045000-7070000,10100000-10130000,14000000-14105000,18068000-18115000,21000000-21155000,24890000-24935000,28000000-28070000,28200000-28300000,50000000-50100000,50400000-50500000"

# ── Per-instance CW segment lists ─────────────────────────────────────────────
# The two SkimSrv instances have separate .ini files and each runs only the
# bands assigned to it, so neither needs the whole plan: a full instance 1 needs
# nine entries and a typical instance 2 three. Building each list from that
# instance's own bands keeps both well under the ceiling above, and leaves the
# room needed to give the 96 kHz NCDXF beacon channels a segment of their own -
# without which SkimSrv allocates them no decoders at all.
#
# 20m and 15m need care: their segments already run past the NCDXF frequency
# (14.105 and 21.155), so when a band and its beacon channel land on the same
# instance the parent is truncated and the beacon segment carries the top
# 10 kHz, rather than emitting two overlapping ranges. Where the beacon channel
# is not on the instance - which includes every 192 kHz configuration, since
# the beacon centres exist only at 96 kHz - the parent keeps its full range and
# the list is exactly what that instance gets today.
#
# Takes the band names on one instance, prints its CwSegments value.
build_segment_list() {
    local names=" $* " out="" name segs seg
    for name in "$@"; do
        case "$name" in
            160M)        segs="1800000-1840000" ;;
            80M)         segs="3500000-3570000" ;;
            60M)         segs="5258500-5358000" ;;
            40M)         segs="7000000-7035000 7045000-7070000" ;;
            30M)         segs="10100000-10130000" ;;
            20M)         case "$names" in
                             *" 20M_BEACONS "*) segs="14000000-14095000" ;;
                             *)                 segs="14000000-14105000" ;;
                         esac ;;
            17M)         segs="18068000-18115000" ;;
            15M)         case "$names" in
                             *" 15M_BEACONS "*) segs="21000000-21145000" ;;
                             *)                 segs="21000000-21155000" ;;
                         esac ;;
            12M)         segs="24890000-24935000" ;;
            10M)         segs="28000000-28070000" ;;
            10M_BEACONS) segs="28200000-28300000" ;;
            6M)          segs="50000000-50100000" ;;
            6M_BEACONS)  segs="50400000-50500000" ;;
            20M_BEACONS) segs="14095000-14105000" ;;
            15M_BEACONS) segs="21145000-21155000" ;;
            *)           segs="" ;;
        esac
        for seg in $segs; do
            out="${out:+$out,}$seg"
        done
    done
    echo "$out"
}

# ── UberSDR tuning range probe ────────────────────────────────────────────────
# Ask the UberSDR instance what it can actually tune. Bands outside its hardware
# range (typically 6m on a receiver that stops at 30 MHz) are then disabled
# automatically, instead of tying up one of the eight SkimSrv slots with a
# segment that can never produce a spot.
#
# Note: curl is not installed in this image — wget is.
UBERSDR_MIN_FREQ=""
UBERSDR_MAX_FREQ=""

probe_tuning_range() {
    local url="http://${UBERSDR_HOST:-ubersdr}:${UBERSDR_PORT:-8080}/api/description"
    local json range attempt
    echo "Querying UberSDR tuning range at $url ..."
    for attempt in 1 2 3; do
        if json=$(wget -q -O - --timeout=5 --tries=1 "$url" 2>/dev/null) && [ -n "$json" ]; then
            # Isolate the tuning_range object first ([^}]* stops at its closing
            # brace), then read the two bounds out of it. Avoids matching
            # similarly-named keys elsewhere in the document.
            range=$(printf '%s' "$json" | sed -n 's/.*"tuning_range"[^{]*{\([^}]*\)}.*/\1/p')
            if [ -n "$range" ]; then
                UBERSDR_MIN_FREQ=$(printf '%s' "$range" | sed -n 's/.*"min_frequency"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
                UBERSDR_MAX_FREQ=$(printf '%s' "$range" | sed -n 's/.*"max_frequency"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')
            fi
            if [ -n "$UBERSDR_MAX_FREQ" ]; then
                echo "UberSDR tuning range: ${UBERSDR_MIN_FREQ:-0} - ${UBERSDR_MAX_FREQ} Hz"
                return 0
            fi
            echo "Warning: no usable tuning_range in API response (attempt $attempt/3)"
        else
            echo "Warning: could not reach $url (attempt $attempt/3)"
        fi
        if [ "$attempt" -lt 3 ]; then sleep 2; fi
    done
    UBERSDR_MIN_FREQ=""
    UBERSDR_MAX_FREQ=""
    echo "Warning: UberSDR tuning range unknown — band availability will not be checked"
    echo "Warning: bands beyond the receiver's range (if any) will be left enabled as configured"
    return 1
}

# Disable any enabled band whose IQ window falls outside the receiver's range.
# SkimSrv asks the SDR for a SAMPLE_RATE-wide window centred on the band's
# centre frequency, so the test is centre +/- SAMPLE_RATE/2 against the bounds.
# Operates on BAND_NAMES / BAND_SEG_IDX / BAND_VARS / CENTER_FREQ_LIST.
apply_tuning_range_gate() {
    local half i name idx centre lo hi gated

    if [ -z "$UBERSDR_MAX_FREQ" ]; then
        return 0
    fi

    half=$(( SAMPLE_RATE * 1000 / 2 ))
    gated=0
    for (( i=0; i<${#BAND_NAMES[@]}; i++ )); do
        if [ "${BAND_VARS[$i]}" != "true" ]; then continue; fi
        name="${BAND_NAMES[$i]}"
        idx="${BAND_SEG_IDX[$i]}"
        centre="${CENTER_FREQ_LIST[$idx]}"
        if [ -z "$centre" ]; then continue; fi
        lo=$(( centre - half ))
        hi=$(( centre + half ))
        if [ "$hi" -gt "$UBERSDR_MAX_FREQ" ] || { [ -n "$UBERSDR_MIN_FREQ" ] && [ "$lo" -lt "$UBERSDR_MIN_FREQ" ]; }; then
            echo "  ${name}: disabled — needs ${lo}-${hi} Hz, receiver covers ${UBERSDR_MIN_FREQ:-0}-${UBERSDR_MAX_FREQ} Hz"
            BAND_VARS[$i]="false"
            printf -v "BAND_${name}" '%s' "false"
            gated=$(( gated + 1 ))
        fi
    done

    if [ "$gated" -gt 0 ]; then
        echo "$gated band(s) disabled as out of range for this receiver"
    else
        echo "All requested bands are within the receiver's tuning range"
    fi
}

# Wipe stale Armadillo license/trial state baked in at image build time.
# This ensures the trial clock starts from container creation, not image build date,
# and that license .reg files are imported onto a clean slate.
echo "Clearing stale Armadillo license registry key..."
DISPLAY=:0 wine reg delete "HKLM\\SOFTWARE\\WOW6432Node\\Licenses" /f 2>/dev/null || true

# Import any .reg files from the skimsrv config directory into the Wine registry
REG_IMPORTED=0
for reg_file in /tmp/skimsrv_licenses/*.reg; do
    if [ -f "$reg_file" ]; then
        echo "Importing Wine registry file: $reg_file"
        DISPLAY=:0 wine regedit "$reg_file"
        REG_IMPORTED=$((REG_IMPORTED + 1))
    fi
done
if [ "$REG_IMPORTED" -eq 0 ]; then
    echo "No .reg files found in /tmp/skimsrv_licenses/ - SkimSrv will run unregistered"
else
    echo "Imported $REG_IMPORTED .reg file(s) into Wine registry"
fi

# Background watcher: export license to licenses/ once it appears in the Wine registry.
# This handles the case where the user enters their serial via the SkimSrv GUI inside
# the container. The watcher polls the Wine system.reg file every 30 seconds, exports
# the Armadillo license blobs when found, then exits (self-terminating).
# Controlled by LICENSE_EXPORT_ENABLED (default false) — disable to prevent the exported
# .reg file from re-injecting trial state (e.g. RttySkimServ trial days) on every restart.
: ${LICENSE_EXPORT_ENABLED:=false}
if [ "$LICENSE_EXPORT_ENABLED" = "true" ] || [ "$LICENSE_EXPORT_ENABLED" = "1" ]; then
    (
        EXPORT_PATH="/tmp/skimsrv_licenses/skimsrv_license_exported.reg"
        WINE_SYSREG="/root/.wine/system.reg"
        echo "License watcher started (will export to licenses/ when registration is detected)"
        while true; do
            sleep 30
            # Check Wine's system.reg directly — no Wine process overhead
            if grep -q "0B3C3B61550D45B7A\|K7C0DB872A3F777C0" "$WINE_SYSREG" 2>/dev/null; then
                echo "License detected in Wine registry — exporting to $EXPORT_PATH"
                DISPLAY=:0 wine reg export "HKLM\\SOFTWARE\\WOW6432Node\\Licenses" "$EXPORT_PATH" /y 2>/dev/null \
                    && echo "License exported successfully to licenses/skimsrv_license_exported.reg" \
                    || echo "License export failed — try manually: wine reg export HKLM\\SOFTWARE\\WOW6432Node\\Licenses /path/to/file.reg"
                exit 0
            fi
        done
    ) &
else
    echo "License watcher disabled (LICENSE_EXPORT_ENABLED=false) — set to true to export license after GUI registration"
fi

# Initialize SkimSrv.ini if it's empty (bind mount created empty file on first run)
if [ -f "$PATH_INI_SKIMSRV" ] && [ ! -s "$PATH_INI_SKIMSRV" ]; then
    echo "Initializing empty SkimSrv.ini with template..."
    cat > "$PATH_INI_SKIMSRV" << EOF
[Window]
MainFormLeft=543
MainFormTop=130
[User]
Call=
Name=
QTH=
Square=
[Telnet]
Port=7300
PasswordRequired=0
Password=
CqOnly=0
AllowAnn=1
AnnUserOnly=0
AnnUser=
MinQuality=1
[Skimmer]
CenterFreqs48=$CENTER_FREQS_48
CenterFreqs96=$CENTER_FREQS_96
CenterFreqs192=$CENTER_FREQS_192
SegmentSel48=00010000000000000
SegmentSel96=0000000000000000
SegmentSel192=0000000000000
CwSegments=$CW_SEGMENTS
ThreadCount=2
DeviceName=01 UberSDR-IQ192
Rate=2
FreqCalibration=1
EOF
fi

# Configure Skimmer Server - always set from .env values
echo "Configuring SkimSrv at $PATH_INI_SKIMSRV"
if [ -f "$PATH_INI_SKIMSRV" ]; then
    echo "Setting SkimSrv with Callsign: $CALLSIGN, QTH: $QTH, Name: $NAME, Grid: $SQUARE"
    # Use temp file for bind-mounted files (sed -i doesn't work on bind mounts)
    # Escape special characters in variables for sed
    CALLSIGN_ESC=$(printf '%s\n' "$CALLSIGN" | sed 's/[[\.*^$/]/\\&/g')
    QTH_ESC=$(printf '%s\n' "$QTH" | sed 's/[[\.*^$/]/\\&/g')
    NAME_ESC=$(printf '%s\n' "$NAME" | sed 's/[[\.*^$/]/\\&/g')
    SQUARE_ESC=$(printf '%s\n' "$SQUARE" | sed 's/[[\.*^$/]/\\&/g')
    
    sed "s/^Call=.*/Call=$CALLSIGN_ESC/g" "$PATH_INI_SKIMSRV" | \
    sed "s/^QTH=.*/QTH=$QTH_ESC/g" | \
    sed "s/^Name=.*/Name=$NAME_ESC/g" | \
    sed "s/^Square=.*/Square=$SQUARE_ESC/g" > "$PATH_INI_SKIMSRV.tmp"
    cat "$PATH_INI_SKIMSRV.tmp" > "$PATH_INI_SKIMSRV"
    rm -f "$PATH_INI_SKIMSRV.tmp"

    # Determine sample rate setting
    : ${SAMPLE_RATE:=192}
    : ${FREQ_CALIBRATION:=1}

    if [ "$SAMPLE_RATE" = "96" ]; then
        RATE_VALUE=1
        SEGMENT_SEL_KEY="SegmentSel96"
        # CenterFreqs96 has 16 entries (index 0-15):
        # 0=160m, 1=80m, 2=60m, 3=40m, 4=30m, 5=20m, 6=17m, 7=15m, 8=12m,
        # 9=10m(low CW), 10=10m(high CW, unused), 11=10m beacons(28.225MHz, covers NCDXF 28.200),
        # 12=6m CW(50.050MHz), 13=6m beacons(50.450MHz, IARU R1 50.400-50.500),
        # 14=20m beacons(14.100MHz, NCDXF), 15=15m beacons(21.150MHz, NCDXF)
        BAND_NAMES=("160M" "80M" "60M" "40M" "30M" "20M" "17M" "15M" "12M" "10M" "10M_BEACONS" "6M" "6M_BEACONS" "20M_BEACONS" "15M_BEACONS")
        BAND_SEG_IDX=(0 1 2 3 4 5 6 7 8 9 11 12 13 14 15)
        SEL_LENGTH=16
        IFS=',' read -r -a CENTER_FREQ_LIST <<< "$CENTER_FREQS_96"
    else
        SAMPLE_RATE=192
        RATE_VALUE=2
        SEGMENT_SEL_KEY="SegmentSel192"
        # CenterFreqs192 has 13 entries (index 0-12):
        # 0=160m, 1=80m, 2=60m, 3=40m, 4=30m, 5=20m, 6=17m, 7=15m, 8=12m,
        # 9=10m CW, 10=10m beacons(28.225MHz, covers NCDXF 28.200),
        # 11=6m CW(50.091MHz), 12=6m beacons(50.450MHz, IARU R1 50.400-50.500)
        # At 192 kHz a single centre covers the whole 6m CW segment, and the
        # standard 20m/15m segments already cover the NCDXF beacon frequencies.
        BAND_NAMES=("160M" "80M" "60M" "40M" "30M" "20M" "17M" "15M" "12M" "10M" "10M_BEACONS" "6M" "6M_BEACONS")
        BAND_SEG_IDX=(0 1 2 3 4 5 6 7 8 9 10 11 12)
        SEL_LENGTH=13
        IFS=',' read -r -a CENTER_FREQ_LIST <<< "$CENTER_FREQS_192"
    fi

    echo "Sample rate: ${SAMPLE_RATE} kHz (Rate=${RATE_VALUE}, key=${SEGMENT_SEL_KEY})"

    # Build SegmentSel based on band enable/disable environment variables
    echo "Building band selection from environment variables..."

    # Default values if not set
    : ${BAND_160M:=false}
    : ${BAND_80M:=true}
    : ${BAND_60M:=true}
    : ${BAND_40M:=true}
    : ${BAND_30M:=true}
    : ${BAND_20M:=true}
    : ${BAND_17M:=true}
    : ${BAND_15M:=true}
    : ${BAND_12M:=true}
    : ${BAND_10M:=true}
    : ${BAND_10M_BEACONS:=true}
    # 6m is opt-in: many UberSDR instances stop at 30 MHz. The installer turns
    # BAND_6M on automatically when the API reports the receiver reaches 6m.
    : ${BAND_6M:=false}
    # 6m beacons (50.400-50.500) are the IARU Region 1 beacon band only.
    : ${BAND_6M_BEACONS:=false}
    : ${BAND_20M_BEACONS:=true}
    : ${BAND_15M_BEACONS:=true}

    # Read each band's flag by name so BAND_NAMES is the single source of
    # ordering — no hand-maintained parallel array to drift out of sync.
    BAND_VARS=()
    for _band_name in "${BAND_NAMES[@]}"; do
        _band_var="BAND_${_band_name}"
        BAND_VARS+=("${!_band_var}")
    done

    # Ask the receiver what it can tune, then drop any band beyond its range
    probe_tuning_range || true
    apply_tuning_range_gate

    # Build list of enabled segment indices
    ENABLED_BANDS=()
    ENABLED_NAMES=()
    BAND_COUNT=${#BAND_SEG_IDX[@]}
    for (( i=0; i<BAND_COUNT; i++ )); do
        if [ "${BAND_VARS[$i]}" = "true" ]; then
            ENABLED_BANDS+=("${BAND_SEG_IDX[$i]}")
            ENABLED_NAMES+=("${BAND_NAMES[$i]}")
        fi
    done

    ENABLED_COUNT=${#ENABLED_BANDS[@]}
    echo "Total enabled bands: $ENABLED_COUNT"

    # Split bands between the two instances (SkimSrv has an 8-band limit each).
    # Instance 1: first 8 enabled bands (or all of them if <=8)
    # Instance 2: the remainder, up to another 8
    MAX_BANDS_PER_INSTANCE=8
    MAX_BANDS_TOTAL=$(( MAX_BANDS_PER_INSTANCE * 2 ))

    if [ $ENABLED_COUNT -gt $MAX_BANDS_TOTAL ]; then
        echo "Warning: $ENABLED_COUNT bands enabled, but only $MAX_BANDS_TOTAL fit across two SkimSrv instances"
        echo "Warning: these bands will NOT be skimmed — disable others to make room:"
        for (( i=MAX_BANDS_TOTAL; i<ENABLED_COUNT; i++ )); do
            echo "Warning:   ${ENABLED_NAMES[$i]}"
        done
    fi

    # Build zero-filled SegmentSel strings of correct length
    SEGMENT_SEL_1=$(printf '0%.0s' $(seq 1 $SEL_LENGTH))
    SEGMENT_SEL_2=$(printf '0%.0s' $(seq 1 $SEL_LENGTH))

    INSTANCE_1_NAMES=()
    INSTANCE_2_NAMES=()

    for (( i=0; i<ENABLED_COUNT && i<MAX_BANDS_PER_INSTANCE; i++ )); do
        seg_idx=${ENABLED_BANDS[$i]}
        SEGMENT_SEL_1="${SEGMENT_SEL_1:0:$seg_idx}1${SEGMENT_SEL_1:$((seg_idx+1))}"
        INSTANCE_1_NAMES+=("${ENABLED_NAMES[$i]}")
    done

    for (( i=MAX_BANDS_PER_INSTANCE; i<ENABLED_COUNT && i<MAX_BANDS_TOTAL; i++ )); do
        seg_idx=${ENABLED_BANDS[$i]}
        SEGMENT_SEL_2="${SEGMENT_SEL_2:0:$seg_idx}1${SEGMENT_SEL_2:$((seg_idx+1))}"
        INSTANCE_2_NAMES+=("${ENABLED_NAMES[$i]}")
    done

    # An instance with no bands keeps the whole-plan list: it decodes nothing
    # either way, and an empty CwSegments is not worth finding out about.
    CW_SEGMENTS_1=$(build_segment_list "${INSTANCE_1_NAMES[@]}")
    CW_SEGMENTS_2=$(build_segment_list "${INSTANCE_2_NAMES[@]}")
    [ -n "$CW_SEGMENTS_1" ] || CW_SEGMENTS_1="$CW_SEGMENTS"
    [ -n "$CW_SEGMENTS_2" ] || CW_SEGMENTS_2="$CW_SEGMENTS"

    if [ $ENABLED_COUNT -le $MAX_BANDS_PER_INSTANCE ]; then
        echo "Instance 1: all $ENABLED_COUNT enabled band(s)"
        echo "Instance 2: no bands (standby)"
    else
        INSTANCE_2_COUNT=$ENABLED_COUNT
        if [ $INSTANCE_2_COUNT -gt $MAX_BANDS_TOTAL ]; then
            INSTANCE_2_COUNT=$MAX_BANDS_TOTAL
        fi
        echo "Instance 1: first $MAX_BANDS_PER_INSTANCE enabled bands"
        echo "Instance 2: remaining $(( INSTANCE_2_COUNT - MAX_BANDS_PER_INSTANCE )) band(s)"
    fi

    echo ""
    echo "Band configuration:"
    for (( i=0; i<BAND_COUNT; i++ )); do
        printf "  %-14s %s\n" "${BAND_NAMES[$i]}:" "${BAND_VARS[$i]}"
    done
    echo ""
    echo "Instance 1 ${SEGMENT_SEL_KEY}: $SEGMENT_SEL_1"
    echo "Instance 2 ${SEGMENT_SEL_KEY}: $SEGMENT_SEL_2"
    echo "Instance 1 CwSegments ($(printf '%s' "$CW_SEGMENTS_1" | awk -F, '{print NF}') entries): $CW_SEGMENTS_1"
    echo "Instance 2 CwSegments ($(printf '%s' "$CW_SEGMENTS_2" | awk -F, '{print NF}') entries): $CW_SEGMENTS_2"

    # Configure instance 1
    echo "Configuring SkimSrv instance 1..."
    sed "s/^CenterFreqs192=.*/CenterFreqs192=$CENTER_FREQS_192/g" "$PATH_INI_SKIMSRV" | \
    sed "s/^CenterFreqs96=.*/CenterFreqs96=$CENTER_FREQS_96/g" | \
    sed "s|^CwSegments=.*|CwSegments=$CW_SEGMENTS_1|g" | \
    sed "s/^${SEGMENT_SEL_KEY}=.*/${SEGMENT_SEL_KEY}=$SEGMENT_SEL_1/g" | \
    sed "s/^Rate=.*/Rate=$RATE_VALUE/g" | \
    sed "s/^Port=.*/Port=7300/g" | \
    sed "s/^FreqCalibration=.*/FreqCalibration=$FREQ_CALIBRATION/g" | \
    sed "s/^MinQuality=.*/MinQuality=${MIN_QUALITY:-1}/g" > "$PATH_INI_SKIMSRV.tmp"
    cat "$PATH_INI_SKIMSRV.tmp" > "$PATH_INI_SKIMSRV"
    rm -f "$PATH_INI_SKIMSRV.tmp"

    echo "SkimSrv instance 1 configured successfully"
fi

# Configure SkimSrv instance 2
echo "Configuring SkimSrv instance 2 at $PATH_INI_SKIMSRV_2"
if [ -f "$PATH_INI_SKIMSRV_2" ]; then
    # Initialize if empty
    if [ ! -s "$PATH_INI_SKIMSRV_2" ]; then
        echo "Initializing empty SkimSrv-2.ini with template..."
        cat > "$PATH_INI_SKIMSRV_2" << EOF
[Window]
MainFormLeft=543
MainFormTop=130
[User]
Call=
Name=
QTH=
Square=
[Telnet]
Port=7301
PasswordRequired=0
Password=
CqOnly=0
AllowAnn=1
AnnUserOnly=0
AnnUser=
MinQuality=1
[Skimmer]
CenterFreqs48=$CENTER_FREQS_48
CenterFreqs96=$CENTER_FREQS_96
CenterFreqs192=$CENTER_FREQS_192
SegmentSel48=00010000000000000
SegmentSel96=0000000000000000
SegmentSel192=0000000000000
CwSegments=$CW_SEGMENTS
ThreadCount=2
DeviceName=01 UberSDR-IQ192
Rate=2
FreqCalibration=1
EOF
    fi

    # Configure with user settings and band selection
    CALLSIGN_ESC=$(printf '%s\n' "$CALLSIGN" | sed 's/[[\.*^$/]/\\&/g')
    QTH_ESC=$(printf '%s\n' "$QTH" | sed 's/[[\.*^$/]/\\&/g')
    NAME_ESC=$(printf '%s\n' "$NAME" | sed 's/[[\.*^$/]/\\&/g')
    SQUARE_ESC=$(printf '%s\n' "$SQUARE" | sed 's/[[\.*^$/]/\\&/g')

    sed "s/^Call=.*/Call=$CALLSIGN_ESC/g" "$PATH_INI_SKIMSRV_2" | \
    sed "s/^QTH=.*/QTH=$QTH_ESC/g" | \
    sed "s/^Name=.*/Name=$NAME_ESC/g" | \
    sed "s/^Square=.*/Square=$SQUARE_ESC/g" | \
    sed "s/^CenterFreqs192=.*/CenterFreqs192=$CENTER_FREQS_192/g" | \
    sed "s/^CenterFreqs96=.*/CenterFreqs96=$CENTER_FREQS_96/g" | \
    sed "s|^CwSegments=.*|CwSegments=$CW_SEGMENTS_2|g" | \
    sed "s/^${SEGMENT_SEL_KEY}=.*/${SEGMENT_SEL_KEY}=$SEGMENT_SEL_2/g" | \
    sed "s/^Rate=.*/Rate=$RATE_VALUE/g" | \
    sed "s/^Port=.*/Port=7301/g" | \
    sed "s/^FreqCalibration=.*/FreqCalibration=$FREQ_CALIBRATION/g" | \
    sed "s/^MinQuality=.*/MinQuality=${MIN_QUALITY:-1}/g" > "$PATH_INI_SKIMSRV_2.tmp"
    cat "$PATH_INI_SKIMSRV_2.tmp" > "$PATH_INI_SKIMSRV_2"
    rm -f "$PATH_INI_SKIMSRV_2.tmp"

    echo "SkimSrv instance 2 configured successfully"
fi

# Configure RBN Aggregator
echo "Configure RBN Aggregator with Callsign: $CALLSIGN using $PATH_INI_AGGREGATOR"
#sed -i 's/Skimmer Call=.*/Skimmer Call='$CALLSIGN'/g' "$PATH_INI_AGGREGATOR"
#cat "$PATH_INI_AGGREGATOR"
sed -i 's/CW0SKIM/'$CALLSIGN'/g' "$PATH_INI_AGGREGATOR"

# Control whether spots are sent to RBN (RBN_SEND_SPOTS=true sends spots, false suppresses them)
: ${RBN_SEND_SPOTS:=true}
if [ "$RBN_SEND_SPOTS" = "true" ]; then
    DONT_SEND_RBN=False
else
    DONT_SEND_RBN=True
fi
echo "RBN spot submission: RBN_SEND_SPOTS=$RBN_SEND_SPOTS -> Don't Send Spots to RBN=$DONT_SEND_RBN"
sed -i "s/^Don't Send Spots to RBN=.*/Don't Send Spots to RBN=$DONT_SEND_RBN/g" "$PATH_INI_AGGREGATOR"

# Configure Secondary Skimmer 1 to connect to SkimSrv instance 2 (port 7301)
echo "Configuring Aggregator Secondary Skimmer 1 for SkimSrv instance 2..."
sed -i "s/^Secondary Skimmer 1 Callsign=.*/Secondary Skimmer 1 Callsign=$CALLSIGN/g" "$PATH_INI_AGGREGATOR"
sed -i 's/^Secondary Skimmer 1 Port=.*/Secondary Skimmer 1 Port=7301/g' "$PATH_INI_AGGREGATOR"
sed -i 's/^Secondary Skimmer 1 Auto Start=.*/Secondary Skimmer 1 Auto Start=True/g' "$PATH_INI_AGGREGATOR"
echo "Aggregator configured to connect to both SkimSrv instances (ports 7300 and 7301)"

# Configure Secondary Skimmer 2 for RttySkimServ (only when enabled)
: ${RTTYSKIRMSRV_ENABLED:=false}
: ${RTTYSKIRMSRV_PORT:=7400}
if [ "$RTTYSKIRMSRV_ENABLED" = "true" ] || [ "$RTTYSKIRMSRV_ENABLED" = "1" ]; then
    echo "Configuring Aggregator Secondary Skimmer 2 for RttySkimServ (port $RTTYSKIRMSRV_PORT)..."
    sed -i "s/^Secondary Skimmer 2 Callsign=.*/Secondary Skimmer 2 Callsign=$CALLSIGN/g" "$PATH_INI_AGGREGATOR"
    sed -i "s/^Secondary Skimmer 2 Port=.*/Secondary Skimmer 2 Port=$RTTYSKIRMSRV_PORT/g" "$PATH_INI_AGGREGATOR"
    sed -i 's/^Secondary Skimmer 2 Auto Start=.*/Secondary Skimmer 2 Auto Start=True/g' "$PATH_INI_AGGREGATOR"
    echo "Aggregator configured to connect to RttySkimServ on port $RTTYSKIRMSRV_PORT"
else
    echo "RTTYSKIRMSRV_ENABLED is false, skipping Secondary Skimmer 2 configuration"
fi

#cat "$PATH_INI_AGGREGATOR"
# FIXME: only debug stuff
cp "$PATH_INI_AGGREGATOR" /root/
chmod oag-r "$PATH_INI_AGGREGATOR"

# Reduced-depth IQ compression margin in dB for the UberSDR driver
# 26 = driver default, 0 = off (lossless), otherwise 15-60. The driver refuses
# anything else and falls back to lossless, so pass the value through unclamped.
: ${MIN_MARGIN:=26}
MIN_MARGIN_ESC=$(printf '%s\n' "$MIN_MARGIN" | sed 's/[[\.*^$/]/\\&/g')

# Initialize UberSDRIntf.ini if it's empty (bind mount created empty file on first run)
if [ -f "$PATH_INI_UBERSDR" ] && [ ! -s "$PATH_INI_UBERSDR" ]; then
    echo "Initializing empty UberSDRIntf.ini with template..."
    cat > "$PATH_INI_UBERSDR" << 'EOF'
; UberSDR Interface Configuration File
[Server]
Host=ubersdr
Port=8080
debug_rec=0

[Calibration]
FrequencyOffset=0
swap_iq=1
EOF
fi

# Configure UberSDR driver - always set from .env values
echo "Configuring UberSDR driver at $PATH_INI_UBERSDR"
if [ -f "$PATH_INI_UBERSDR" ]; then
    echo "Setting UberSDR driver with host: $UBERSDR_HOST, port: $UBERSDR_PORT, min_margin: $MIN_MARGIN"
    # Use temp file for bind-mounted files (sed -i doesn't work on bind mounts)
    # Escape special characters in variables for sed
    UBERSDR_HOST_ESC=$(printf '%s\n' "$UBERSDR_HOST" | sed 's/[[\.*^$/]/\\&/g')
    UBERSDR_PORT_ESC=$(printf '%s\n' "$UBERSDR_PORT" | sed 's/[[\.*^$/]/\\&/g')

    sed "s/^Host=.*/Host=$UBERSDR_HOST_ESC/g" "$PATH_INI_UBERSDR" | \
    sed "s/^Port=.*/Port=$UBERSDR_PORT_ESC/g" | \
    sed "s/^min_margin=.*/min_margin=$MIN_MARGIN_ESC/g" > "$PATH_INI_UBERSDR.tmp"
    # Older driver inis (and the empty-file template above) have no
    # min_margin line at all - insert one into [Server] so the setting
    # is always explicit rather than falling back to the driver default
    if ! grep -q "^min_margin=" "$PATH_INI_UBERSDR.tmp"; then
        sed "s/^\[Server\]/[Server]\\nmin_margin=$MIN_MARGIN_ESC/" "$PATH_INI_UBERSDR.tmp" > "$PATH_INI_UBERSDR.tmp2"
        mv "$PATH_INI_UBERSDR.tmp2" "$PATH_INI_UBERSDR.tmp"
    fi
    cat "$PATH_INI_UBERSDR.tmp" > "$PATH_INI_UBERSDR"
    rm -f "$PATH_INI_UBERSDR.tmp"
    echo "UberSDRIntf.ini configured successfully"
else
    echo "Warning: UberSDRIntf.ini not found at $PATH_INI_UBERSDR"
fi

# Initialize UberSDRIntf-2.ini if it's empty (bind mount created empty file on first run)
if [ -f "$PATH_INI_UBERSDR_2" ] && [ ! -s "$PATH_INI_UBERSDR_2" ]; then
    echo "Initializing empty UberSDRIntf-2.ini with template..."
    cat > "$PATH_INI_UBERSDR_2" << 'EOF'
; UberSDR Interface Configuration File
[Server]
Host=ubersdr
Port=8080
debug_rec=0

[Calibration]
FrequencyOffset=0
swap_iq=1
EOF
fi

# Configure UberSDR driver for instance 2 - always set from .env values
echo "Configuring UberSDR driver for instance 2 at $PATH_INI_UBERSDR_2"
if [ -f "$PATH_INI_UBERSDR_2" ]; then
    echo "Setting UberSDR driver instance 2 with host: $UBERSDR_HOST, port: $UBERSDR_PORT, min_margin: $MIN_MARGIN"
    # Use temp file for bind-mounted files (sed -i doesn't work on bind mounts)
    # Escape special characters in variables for sed
    UBERSDR_HOST_ESC=$(printf '%s\n' "$UBERSDR_HOST" | sed 's/[[\.*^$/]/\\&/g')
    UBERSDR_PORT_ESC=$(printf '%s\n' "$UBERSDR_PORT" | sed 's/[[\.*^$/]/\\&/g')

    sed "s/^Host=.*/Host=$UBERSDR_HOST_ESC/g" "$PATH_INI_UBERSDR_2" | \
    sed "s/^Port=.*/Port=$UBERSDR_PORT_ESC/g" | \
    sed "s/^min_margin=.*/min_margin=$MIN_MARGIN_ESC/g" > "$PATH_INI_UBERSDR_2.tmp"
    # Older driver inis (and the empty-file template above) have no
    # min_margin line at all - insert one into [Server] so the setting
    # is always explicit rather than falling back to the driver default
    if ! grep -q "^min_margin=" "$PATH_INI_UBERSDR_2.tmp"; then
        sed "s/^\[Server\]/[Server]\\nmin_margin=$MIN_MARGIN_ESC/" "$PATH_INI_UBERSDR_2.tmp" > "$PATH_INI_UBERSDR_2.tmp2"
        mv "$PATH_INI_UBERSDR_2.tmp2" "$PATH_INI_UBERSDR_2.tmp"
    fi
    cat "$PATH_INI_UBERSDR_2.tmp" > "$PATH_INI_UBERSDR_2"
    rm -f "$PATH_INI_UBERSDR_2.tmp"
    echo "UberSDRIntf-2.ini configured successfully"
else
    echo "Warning: UberSDRIntf-2.ini not found at $PATH_INI_UBERSDR_2"
fi

# Initialize UberSDRIntf.ini for RttySkimServ if it's empty
if [ -f "$PATH_INI_UBERSDR_RTTY" ] && [ ! -s "$PATH_INI_UBERSDR_RTTY" ]; then
    echo "Initializing empty UberSDRIntf.ini (RttySkimServ) with template..."
    cat > "$PATH_INI_UBERSDR_RTTY" << 'EOF'
; UberSDR Interface Configuration File
[Server]
Host=ubersdr
Port=8080
debug_rec=0

[Calibration]
FrequencyOffset=0
swap_iq=1
EOF
fi

# Configure UberSDR driver for RttySkimServ - always set from .env values
echo "Configuring UberSDR driver for RttySkimServ at $PATH_INI_UBERSDR_RTTY"
if [ -f "$PATH_INI_UBERSDR_RTTY" ]; then
    echo "Setting UberSDR driver (RttySkimServ) with host: $UBERSDR_HOST, port: $UBERSDR_PORT, min_margin: $MIN_MARGIN"
    UBERSDR_HOST_ESC=$(printf '%s\n' "$UBERSDR_HOST" | sed 's/[[\.*^$/]/\\&/g')
    UBERSDR_PORT_ESC=$(printf '%s\n' "$UBERSDR_PORT" | sed 's/[[\.*^$/]/\\&/g')

    sed "s/^Host=.*/Host=$UBERSDR_HOST_ESC/g" "$PATH_INI_UBERSDR_RTTY" | \
    sed "s/^Port=.*/Port=$UBERSDR_PORT_ESC/g" | \
    sed "s/^min_margin=.*/min_margin=$MIN_MARGIN_ESC/g" > "$PATH_INI_UBERSDR_RTTY.tmp"
    # Older driver inis (and the empty-file template above) have no
    # min_margin line at all - insert one into [Server] so the setting
    # is always explicit rather than falling back to the driver default
    if ! grep -q "^min_margin=" "$PATH_INI_UBERSDR_RTTY.tmp"; then
        sed "s/^\[Server\]/[Server]\\nmin_margin=$MIN_MARGIN_ESC/" "$PATH_INI_UBERSDR_RTTY.tmp" > "$PATH_INI_UBERSDR_RTTY.tmp2"
        mv "$PATH_INI_UBERSDR_RTTY.tmp2" "$PATH_INI_UBERSDR_RTTY.tmp"
    fi
    cat "$PATH_INI_UBERSDR_RTTY.tmp" > "$PATH_INI_UBERSDR_RTTY"
    rm -f "$PATH_INI_UBERSDR_RTTY.tmp"
    echo "UberSDRIntf.ini (RttySkimServ) configured successfully"
else
    echo "Warning: UberSDRIntf.ini not found at $PATH_INI_UBERSDR_RTTY"
fi

# Configure RttySkimServ
: ${RTTYSKIRMSRV_ENABLED:=false}
: ${RTTYSKIRMSRV_PORT:=7400}
echo "Configuring RttySkimServ at $PATH_INI_RTTYSKIRMSRV (enabled=$RTTYSKIRMSRV_ENABLED)"
if [ -f "$PATH_INI_RTTYSKIRMSRV" ]; then
    CALLSIGN_ESC=$(printf '%s\n' "$CALLSIGN" | sed 's/[[\.*^$/]/\\&/g')
    QTH_ESC=$(printf '%s\n' "$QTH" | sed 's/[[\.*^$/]/\\&/g')
    NAME_ESC=$(printf '%s\n' "$NAME" | sed 's/[[\.*^$/]/\\&/g')
    SQUARE_ESC=$(printf '%s\n' "$SQUARE" | sed 's/[[\.*^$/]/\\&/g')

    # Build RTTY SegmentSel192 from RTTY_BAND_* environment variables
    # CenterFreqs192 index mapping: 0=160m 1=80m 2=60m 3=40m 4=30m 5=20m 6=17m 7=15m 8=12m 9=10m 10=10m(high)
    : ${RTTY_BAND_160M:=false}
    : ${RTTY_BAND_80M:=false}
    : ${RTTY_BAND_60M:=false}
    : ${RTTY_BAND_40M:=true}
    : ${RTTY_BAND_30M:=false}
    : ${RTTY_BAND_20M:=true}
    : ${RTTY_BAND_17M:=false}
    : ${RTTY_BAND_15M:=false}
    : ${RTTY_BAND_12M:=false}
    : ${RTTY_BAND_10M:=false}
    : ${RTTY_BAND_10M_HIGH:=false}

    RTTY_BAND_VARS=("$RTTY_BAND_160M" "$RTTY_BAND_80M" "$RTTY_BAND_60M" "$RTTY_BAND_40M" "$RTTY_BAND_30M" "$RTTY_BAND_20M" "$RTTY_BAND_17M" "$RTTY_BAND_15M" "$RTTY_BAND_12M" "$RTTY_BAND_10M" "$RTTY_BAND_10M_HIGH")
    RTTY_BAND_NAMES=("160M" "80M" "60M" "40M" "30M" "20M" "17M" "15M" "12M" "10M" "10M_HIGH")

    RTTY_SEGMENT_SEL=$(printf '0%.0s' $(seq 1 11))
    for i in {0..10}; do
        if [ "${RTTY_BAND_VARS[$i]}" = "true" ]; then
            RTTY_SEGMENT_SEL="${RTTY_SEGMENT_SEL:0:$i}1${RTTY_SEGMENT_SEL:$((i+1))}"
        fi
    done

    echo ""
    echo "RTTY band configuration:"
    for i in {0..10}; do
        echo "  ${RTTY_BAND_NAMES[$i]}: ${RTTY_BAND_VARS[$i]}"
    done
    echo "RTTY SegmentSel192: $RTTY_SEGMENT_SEL"
    echo ""

    sed "s/^Call=.*/Call=$CALLSIGN_ESC/g" "$PATH_INI_RTTYSKIRMSRV" | \
    sed "s/^Name=.*/Name=$NAME_ESC/g" | \
    sed "s/^QTH=.*/QTH=$QTH_ESC/g" | \
    sed "s/^Square=.*/Square=$SQUARE_ESC/g" | \
    sed "s/^Port=.*/Port=$RTTYSKIRMSRV_PORT/g" | \
    sed "s/^FreqCalibration=.*/FreqCalibration=$FREQ_CALIBRATION/g" | \
    sed "s/^SegmentSel192=.*/SegmentSel192=$RTTY_SEGMENT_SEL/g" | \
    sed "s/^ValidationLevel=.*/ValidationLevel=${RTTY_VALIDATION_LEVEL:-2}/g" > "$PATH_INI_RTTYSKIRMSRV.tmp"
    cat "$PATH_INI_RTTYSKIRMSRV.tmp" > "$PATH_INI_RTTYSKIRMSRV"
    rm -f "$PATH_INI_RTTYSKIRMSRV.tmp"
    echo "RttySkimServ.ini configured successfully"
else
    echo "Warning: RttySkimServ.ini not found at $PATH_INI_RTTYSKIRMSRV"
fi

echo "Configure supervisor for aggregator ${V_RBNAGGREGATOR}"
sed -i 's/6\.3/'$V_RBNAGGREGATOR'/g' /etc/supervisor/conf.d/supervisord.conf

echo "Configure supervisor for skimmer ${V_SKIMMERSRV}"
sed -i 's/1\.6/'$V_SKIMMERSRV'/g' /etc/supervisor/conf.d/supervisord.conf

# Control RttySkimServ startup based on RTTYSKIRMSRV_ENABLED flag
if [ "$RTTYSKIRMSRV_ENABLED" = "true" ] || [ "$RTTYSKIRMSRV_ENABLED" = "1" ]; then
    echo "RTTYSKIRMSRV_ENABLED is true, enabling RttySkimServ in supervisord..."
    sed -i '/\[program:rttyskirmsrv\]/,/^\[/s/autostart=false/autostart=true/' /etc/supervisor/conf.d/supervisord.conf
else
    echo "RTTYSKIRMSRV_ENABLED is false, RttySkimServ will not start"
fi

echo "Start using logfiles $LOGFILE_UBERSDR and $LOGIFLE_AGGREGATOR"
touch $LOGFILE_UBERSDR
touch $LOGIFLE_AGGREGATOR

tail -f $LOGFILE_UBERSDR $LOGIFLE_AGGREGATOR &

# Fetch latest patt3ch.lst from RBN server
PATT3CH_URL="https://data.reversebeacon.net/downloads/patt3ch/patt3ch.lst"
PATT3CH_DEST="/root/.wine/drive_c/users/root/AppData/Roaming/Afreet/Reference/Patt3Ch.lst"
PATT3CH_MAX_ATTEMPTS=3
PATT3CH_RETRY_DELAY=2

echo "Fetching latest patt3ch.lst from $PATT3CH_URL ..."
PATT3CH_SUCCESS=false
for attempt in $(seq 1 $PATT3CH_MAX_ATTEMPTS); do
    if wget -q -O "${PATT3CH_DEST}.tmp" "$PATT3CH_URL"; then
        mv "${PATT3CH_DEST}.tmp" "$PATT3CH_DEST"
        echo "patt3ch.lst updated successfully (attempt $attempt)"
        PATT3CH_SUCCESS=true
        break
    else
        echo "patt3ch.lst fetch failed (attempt $attempt/$PATT3CH_MAX_ATTEMPTS)"
        rm -f "${PATT3CH_DEST}.tmp"
        if [ $attempt -lt $PATT3CH_MAX_ATTEMPTS ]; then
            sleep $PATT3CH_RETRY_DELAY
        fi
    fi
done

if [ "$PATT3CH_SUCCESS" = "false" ]; then
    echo "Warning: Could not fetch patt3ch.lst after $PATT3CH_MAX_ATTEMPTS attempts — using bundled file"
fi

exec "$@"
