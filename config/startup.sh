#!/bin/bash
#set d -e

# Ensure restart trigger directory exists
mkdir -p /var/run/restart-trigger

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

# Initialize SkimSrv.ini if it's empty (bind mount created empty file on first run)
if [ -f "$PATH_INI_SKIMSRV" ] && [ ! -s "$PATH_INI_SKIMSRV" ]; then
    echo "Initializing empty SkimSrv.ini with template..."
    cat > "$PATH_INI_SKIMSRV" << 'EOF'
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
MinQuality=0
[Skimmer]
CenterFreqs48=1822750,3522750,3568250,7022750,10122750,14022750,14068250,18090750,21022750,21068250,24912750,28022750,28068250,50022750,50068250,50113750,50159250
CenterFreqs96=1845500,3545500,5306500,7045500,10145500,14045500,18113500,21045500,24935500,28045500,28136500,28250000,50045500,50136500
CenterFreqs192=1891000,3591000,5355000,7091000,10191000,14091000,18159000,21091000,24981000,28091000,28250000
SegmentSel48=00010000000000000
SegmentSel96=00111111111000
SegmentSel192=01111111111
CwSegments=1800000-1840000,3500000-3570000,5258500-5358000,7000000-7035000,7045000-7070000,10100000-10130000,14000000-14070000,18068000-18095000,21000000-21070000,24890000-24920000,28000000-28070000,28200000-28300000,50000000-50100000
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
        # CenterFreqs96 has 14 entries (index 0-13):
        # 0=160m, 1=80m, 2=60m, 3=40m, 4=30m, 5=20m, 6=17m, 7=15m, 8=12m,
        # 9=10m(low CW), 10=10m(high CW), 11=10m beacons(28.25MHz), 12=6m(low), 13=6m(high)
        BAND_NAMES=("160M" "80M" "60M" "40M" "30M" "20M" "17M" "15M" "12M" "10M" "10M_BEACONS")
        BAND_SEG_IDX=(0 1 2 3 4 5 6 7 8 9 11)
        SEL_LENGTH=14
    else
        SAMPLE_RATE=192
        RATE_VALUE=2
        SEGMENT_SEL_KEY="SegmentSel192"
        # CenterFreqs192 has 11 entries (index 0-10):
        # 0=160m, 1=80m, 2=60m, 3=40m, 4=30m, 5=20m, 6=17m, 7=15m, 8=12m,
        # 9=10m CW, 10=10m beacons(28.25MHz)
        BAND_NAMES=("160M" "80M" "60M" "40M" "30M" "20M" "17M" "15M" "12M" "10M" "10M_BEACONS")
        BAND_SEG_IDX=(0 1 2 3 4 5 6 7 8 9 10)
        SEL_LENGTH=11
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

    BAND_VARS=("$BAND_160M" "$BAND_80M" "$BAND_60M" "$BAND_40M" "$BAND_30M" "$BAND_20M" "$BAND_17M" "$BAND_15M" "$BAND_12M" "$BAND_10M" "$BAND_10M_BEACONS")

    # Build list of enabled segment indices
    ENABLED_BANDS=()
    for i in {0..10}; do
        if [ "${BAND_VARS[$i]}" = "true" ]; then
            ENABLED_BANDS+=("${BAND_SEG_IDX[$i]}")
        fi
    done

    ENABLED_COUNT=${#ENABLED_BANDS[@]}
    echo "Total enabled bands: $ENABLED_COUNT"

    # Split bands between two instances (SkimSrv has 8-band limit)
    # Instance 1: First 8 enabled bands (or all if <=8)
    # Instance 2: Remaining bands (9th and 10th if enabled)

    # Build zero-filled SegmentSel strings of correct length
    SEGMENT_SEL_1=$(printf '0%.0s' $(seq 1 $SEL_LENGTH))
    SEGMENT_SEL_2=$(printf '0%.0s' $(seq 1 $SEL_LENGTH))

    if [ $ENABLED_COUNT -le 8 ]; then
        # All bands go to instance 1
        for seg_idx in "${ENABLED_BANDS[@]}"; do
            SEGMENT_SEL_1="${SEGMENT_SEL_1:0:$seg_idx}1${SEGMENT_SEL_1:$((seg_idx+1))}"
        done
        echo "Instance 1: All $ENABLED_COUNT enabled bands"
        echo "Instance 2: No bands (standby)"
    else
        # First 8 bands to instance 1, remaining to instance 2
        for i in {0..7}; do
            if [ $i -lt $ENABLED_COUNT ]; then
                seg_idx=${ENABLED_BANDS[$i]}
                SEGMENT_SEL_1="${SEGMENT_SEL_1:0:$seg_idx}1${SEGMENT_SEL_1:$((seg_idx+1))}"
            fi
        done

        for i in {8..10}; do
            if [ $i -lt $ENABLED_COUNT ]; then
                seg_idx=${ENABLED_BANDS[$i]}
                SEGMENT_SEL_2="${SEGMENT_SEL_2:0:$seg_idx}1${SEGMENT_SEL_2:$((seg_idx+1))}"
            fi
        done
        echo "Instance 1: First 8 enabled bands"
        echo "Instance 2: Remaining $((ENABLED_COUNT - 8)) band(s)"
    fi

    echo ""
    echo "Band configuration:"
    echo "  160m:         $BAND_160M"
    echo "  80m:          $BAND_80M"
    echo "  60m:          $BAND_60M"
    echo "  40m:          $BAND_40M"
    echo "  30m:          $BAND_30M"
    echo "  20m:          $BAND_20M"
    echo "  17m:          $BAND_17M"
    echo "  15m:          $BAND_15M"
    echo "  12m:          $BAND_12M"
    echo "  10m:          $BAND_10M"
    echo "  10m beacons:  $BAND_10M_BEACONS"
    echo ""
    echo "Instance 1 ${SEGMENT_SEL_KEY}: $SEGMENT_SEL_1"
    echo "Instance 2 ${SEGMENT_SEL_KEY}: $SEGMENT_SEL_2"

    # Configure instance 1
    echo "Configuring SkimSrv instance 1..."
    sed "s/^CenterFreqs192=.*/CenterFreqs192=1891000,3591000,5355000,7091000,10191000,14091000,18159000,21091000,24981000,28091000,28250000/g" "$PATH_INI_SKIMSRV" | \
    sed "s/^CenterFreqs96=.*/CenterFreqs96=1845500,3545500,5306500,7045500,10145500,14045500,18113500,21045500,24935500,28045500,28136500,28250000,50045500,50136500/g" | \
    sed "s|^CwSegments=.*|CwSegments=1800000-1840000,3500000-3570000,5258500-5358000,7000000-7035000,7045000-7070000,10100000-10130000,14000000-14070000,18068000-18095000,21000000-21070000,24890000-24920000,28000000-28070000,28200000-28300000,50000000-50100000|g" | \
    sed "s/^${SEGMENT_SEL_KEY}=.*/${SEGMENT_SEL_KEY}=$SEGMENT_SEL_1/g" | \
    sed "s/^Rate=.*/Rate=$RATE_VALUE/g" | \
    sed "s/^Port=.*/Port=7300/g" | \
    sed "s/^FreqCalibration=.*/FreqCalibration=$FREQ_CALIBRATION/g" | \
    sed "s/^MinQuality=.*/MinQuality=${MIN_QUALITY:-0}/g" > "$PATH_INI_SKIMSRV.tmp"
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
        cat > "$PATH_INI_SKIMSRV_2" << 'EOF'
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
MinQuality=0
[Skimmer]
CenterFreqs48=1822750,3522750,3568250,7022750,10122750,14022750,14068250,18090750,21022750,21068250,24912750,28022750,28068250,50022750,50068250,50113750,50159250
CenterFreqs96=1845500,3545500,5306500,7045500,10145500,14045500,18113500,21045500,24935500,28045500,28136500,28250000,50045500,50136500
CenterFreqs192=1891000,3591000,5355000,7091000,10191000,14091000,18159000,21091000,24981000,28091000,28250000
SegmentSel48=00010000000000000
SegmentSel96=00000000000000
SegmentSel192=00000000000
CwSegments=1800000-1840000,3500000-3570000,5258500-5358000,7000000-7035000,7045000-7070000,10100000-10130000,14000000-14070000,18068000-18095000,21000000-21070000,24890000-24920000,28000000-28070000,28200000-28300000,50000000-50100000
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
    sed "s/^CenterFreqs192=.*/CenterFreqs192=1891000,3591000,5355000,7091000,10191000,14091000,18159000,21091000,24981000,28091000,28250000/g" | \
    sed "s/^CenterFreqs96=.*/CenterFreqs96=1845500,3545500,5306500,7045500,10145500,14045500,18113500,21045500,24935500,28045500,28136500,28250000,50045500,50136500/g" | \
    sed "s|^CwSegments=.*|CwSegments=1800000-1840000,3500000-3570000,5258500-5358000,7000000-7035000,7045000-7070000,10100000-10130000,14000000-14070000,18068000-18095000,21000000-21070000,24890000-24920000,28000000-28070000,28200000-28300000,50000000-50100000|g" | \
    sed "s/^${SEGMENT_SEL_KEY}=.*/${SEGMENT_SEL_KEY}=$SEGMENT_SEL_2/g" | \
    sed "s/^Rate=.*/Rate=$RATE_VALUE/g" | \
    sed "s/^Port=.*/Port=7301/g" | \
    sed "s/^FreqCalibration=.*/FreqCalibration=$FREQ_CALIBRATION/g" | \
    sed "s/^MinQuality=.*/MinQuality=${MIN_QUALITY:-0}/g" > "$PATH_INI_SKIMSRV_2.tmp"
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
    echo "Setting UberSDR driver with host: $UBERSDR_HOST, port: $UBERSDR_PORT"
    # Use temp file for bind-mounted files (sed -i doesn't work on bind mounts)
    # Escape special characters in variables for sed
    UBERSDR_HOST_ESC=$(printf '%s\n' "$UBERSDR_HOST" | sed 's/[[\.*^$/]/\\&/g')
    UBERSDR_PORT_ESC=$(printf '%s\n' "$UBERSDR_PORT" | sed 's/[[\.*^$/]/\\&/g')

    sed "s/^Host=.*/Host=$UBERSDR_HOST_ESC/g" "$PATH_INI_UBERSDR" | \
    sed "s/^Port=.*/Port=$UBERSDR_PORT_ESC/g" > "$PATH_INI_UBERSDR.tmp"
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
    echo "Setting UberSDR driver instance 2 with host: $UBERSDR_HOST, port: $UBERSDR_PORT"
    # Use temp file for bind-mounted files (sed -i doesn't work on bind mounts)
    # Escape special characters in variables for sed
    UBERSDR_HOST_ESC=$(printf '%s\n' "$UBERSDR_HOST" | sed 's/[[\.*^$/]/\\&/g')
    UBERSDR_PORT_ESC=$(printf '%s\n' "$UBERSDR_PORT" | sed 's/[[\.*^$/]/\\&/g')

    sed "s/^Host=.*/Host=$UBERSDR_HOST_ESC/g" "$PATH_INI_UBERSDR_2" | \
    sed "s/^Port=.*/Port=$UBERSDR_PORT_ESC/g" > "$PATH_INI_UBERSDR_2.tmp"
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
    echo "Setting UberSDR driver (RttySkimServ) with host: $UBERSDR_HOST, port: $UBERSDR_PORT"
    UBERSDR_HOST_ESC=$(printf '%s\n' "$UBERSDR_HOST" | sed 's/[[\.*^$/]/\\&/g')
    UBERSDR_PORT_ESC=$(printf '%s\n' "$UBERSDR_PORT" | sed 's/[[\.*^$/]/\\&/g')

    sed "s/^Host=.*/Host=$UBERSDR_HOST_ESC/g" "$PATH_INI_UBERSDR_RTTY" | \
    sed "s/^Port=.*/Port=$UBERSDR_PORT_ESC/g" > "$PATH_INI_UBERSDR_RTTY.tmp"
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

    sed "s/^Call=.*/Call=$CALLSIGN_ESC/g" "$PATH_INI_RTTYSKIRMSRV" | \
    sed "s/^Name=.*/Name=$NAME_ESC/g" | \
    sed "s/^QTH=.*/QTH=$QTH_ESC/g" | \
    sed "s/^Square=.*/Square=$SQUARE_ESC/g" | \
    sed "s/^Port=.*/Port=$RTTYSKIRMSRV_PORT/g" | \
    sed "s/^FreqCalibration=.*/FreqCalibration=$FREQ_CALIBRATION/g" > "$PATH_INI_RTTYSKIRMSRV.tmp"
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


exec "$@"
