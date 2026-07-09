FROM debian:bookworm AS wine

# Install Wine, XFCE, network audio stuff
ENV HOME=/root
ENV DEBIAN_FRONTEND=noninteractive
ENV LC_ALL=C.UTF-8
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US.UTF-8
RUN dpkg --add-architecture i386
RUN apt-get update && apt-get -y install vim cabextract xvfb novnc x11vnc xdotool wget tar dbus-x11 supervisor net-tools gnupg2 procps wine xfce4 innoextract unzip fonts-liberation fonts-dejavu-core
# Contrib enable
#RUN sed -r -i 's/^deb(.*)$/deb\1 contrib/g' /etc/apt/sources.list
#RUN apt-get -qqy autoclean && rm -rf /tmp/* /var/tmp/*
ENV DISPLAY=:0

# Winetricks update
WORKDIR /root/
RUN wget  https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
RUN chmod +x winetricks 
RUN mv -v winetricks /usr/local/bin

# Deps for RBNAggregator
RUN /usr/local/bin/winetricks -q dotnet46 corefonts gdiplus tahoma fontsmooth=rgb

# Fix font configuration for .NET applications
RUN wine reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\FontSubstitutes" /v "MS Shell Dlg" /d "Tahoma" /f
RUN wine reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\FontSubstitutes" /v "MS Shell Dlg 2" /d "Tahoma" /f

FROM wine AS installation

ENV V_SKIMMER=2.1
ENV V_SKIMMERSRV=1.6
ENV V_RTTYSKIRMSRV=1.3
ENV V_RBNAGGREGATOR=6.7

# Copy installation files and extract them
COPY install /install
WORKDIR /skimmer_1.9
RUN  unzip /install/Skimmer_1.9/CwSkimmer.zip && innoextract Setup.exe
WORKDIR /skimmer_${V_SKIMMER}
RUN unzip /install/Skimmer_${V_SKIMMER}/CwSkimmer.zip && innoextract Setup.exe
WORKDIR /skimmersrv_${V_SKIMMERSRV}
RUN unzip /install/SkimmerSrv_${V_SKIMMERSRV}/SkimSrv.zip && innoextract Setup.exe
WORKDIR /rttyskirmsrv_${V_RTTYSKIRMSRV}
RUN unzip /install/RttySkimmer/RttySkimServ.zip && innoextract Setup.exe

# Download and install RBN Aggregator v6.7
WORKDIR /rbnaggregator_${V_RBNAGGREGATOR}
RUN wget -O "Aggregator v${V_RBNAGGREGATOR}.exe" "https://cms.reversebeacon.net/sites/cms.reversebeacon.net/files/2025/02/21/Aggregator%20v6.7.exe"

# Download and install ka9q_ubersdr CW_Skimmer driver
WORKDIR /ubersdr_driver
RUN wget https://github.com/madpsy/ka9q_ubersdr/releases/download/latest/CW_Skimmer.zip
RUN unzip CW_Skimmer.zip

# Add late installer
COPY ./install.sh /install

WORKDIR /root/

FROM installation AS config

# XFCE config
COPY ./config/xfce4 /root/.config/xfce4
# Add startup stuff
COPY ./config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY ./config/startup.sh /bin
COPY ./config/startup_sound.sh /bin
COPY ./config/cwskimmer-entrypoint.sh /bin
RUN chmod +x /bin/cwskimmer-entrypoint.sh

# Aggregator launch wrapper (relaunches Wine + resizes the window on every
# start/restart, including after a crash - see config/supervisord.conf)
RUN mkdir -p /rbn
COPY ./config/rbn/run-aggregator.sh /rbn/run-aggregator.sh
RUN chmod +x /rbn/run-aggregator.sh

# Configuration stuff
ENV PATH_INI_SKIMSRV="/root/.wine/drive_c/users/root/AppData/Roaming/Afreet/Products/SkimSrv/SkimSrv.ini"
ENV PATH_INI_SKIMSRV_2="/root/.wine/drive_c/users/root/AppData/Roaming/Afreet/Products/SkimSrv-2/SkimSrv-2.ini"
ENV PATH_INI_RTTYSKIRMSRV="/root/.wine/drive_c/users/root/AppData/Roaming/Afreet/Products/RttySkimServ/RttySkimServ.ini"
ENV PATH_INI_AGGREGATOR="/rbnaggregator_${V_RBNAGGREGATOR}/Aggregator.ini"
ENV PATH_INI_UBERSDR="/skimmersrv_${V_SKIMMERSRV}/app/UberSDRIntf.ini"
ENV PATH_INI_UBERSDR_2="/skimmersrv_${V_SKIMMERSRV}-2/app/UberSDRIntf.ini"
ENV PATH_INI_UBERSDR_RTTY="/rttyskirmsrv_${V_RTTYSKIRMSRV}/app/UberSDRIntf.ini"

# Create directories for both SkimSrv instances, RttySkimServ, and shared Reference/UserData
RUN mkdir -p $(dirname ${PATH_INI_SKIMSRV})
RUN mkdir -p $(dirname ${PATH_INI_SKIMSRV_2})
RUN mkdir -p $(dirname ${PATH_INI_RTTYSKIRMSRV})
RUN mkdir -p /root/.wine/drive_c/users/root/AppData/Roaming/Afreet/Reference
RUN mkdir -p /root/.wine/drive_c/users/root/AppData/Roaming/Afreet/UserData

# Configure first SkimSrv instance
COPY ./config/rbn/Aggregator.ini ${PATH_INI_AGGREGATOR}
COPY ./config/skimsrv/SkimSrv.ini ${PATH_INI_SKIMSRV}
RUN cp /ubersdr_driver/* /skimmersrv_${V_SKIMMERSRV}/app/
RUN rm -f /skimmersrv_${V_SKIMMERSRV}/app/Qs1rIntf.dll

# Configure RttySkimServ instance
COPY ./config/rttyskirmsrv/RttySkimServ.ini ${PATH_INI_RTTYSKIRMSRV}
RUN cp /ubersdr_driver/* /rttyskirmsrv_${V_RTTYSKIRMSRV}/app/
RUN rm -f /rttyskirmsrv_${V_RTTYSKIRMSRV}/app/Qs1rIntf.dll
# Copy userappdata files extracted by innoextract to correct Wine AppData locations
RUN cp /rttyskirmsrv_${V_RTTYSKIRMSRV}/userappdata/Afreet/Products/RttySkimServ/Contests.ini \
       $(dirname ${PATH_INI_RTTYSKIRMSRV})/Contests.ini
RUN cp /rttyskirmsrv_${V_RTTYSKIRMSRV}/userappdata/Afreet/Reference/MASTER.DTA \
       /root/.wine/drive_c/users/root/AppData/Roaming/Afreet/Reference/MASTER.DTA
RUN cp /rttyskirmsrv_${V_RTTYSKIRMSRV}/userappdata/Afreet/Reference/Black.lst \
       /root/.wine/drive_c/users/root/AppData/Roaming/Afreet/Reference/Black.lst
COPY ./config/skimsrv/Watch.lst \
     /root/.wine/drive_c/users/root/AppData/Roaming/Afreet/UserData/Watch.lst

# Copy patt3ch.lst to shared Reference directory (used by both SkimSrv instances)
COPY ./install/patt3ch/patt3ch.lst /root/.wine/drive_c/users/root/AppData/Roaming/Afreet/Reference/Patt3Ch.lst

# Create second SkimSrv instance by copying the first
RUN cp -r /skimmersrv_${V_SKIMMERSRV} /skimmersrv_${V_SKIMMERSRV}-2
RUN mv /skimmersrv_${V_SKIMMERSRV}-2/app/SkimSrv.exe /skimmersrv_${V_SKIMMERSRV}-2/app/SkimSrv-2.exe
COPY ./config/skimsrv/SkimSrv.ini ${PATH_INI_SKIMSRV_2}

ENV LOGFILE_UBERSDR=/root/ubersdr_driver_log_file.txt
ENV LOGIFLE_AGGREGATOR=/root/AggregatorLog.txt

## Configuration
ENV QTH="Dalgety Bay"
ENV NAME="Nathan"
ENV SQUARE=IO86ha
ENV UBERSDR_HOST=ka9q_ubersdr
ENV UBERSDR_PORT=8080

EXPOSE 7373
EXPOSE 7300
EXPOSE 7550

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD timeout 5 bash -c '</dev/tcp/localhost/7300' || exit 1

ENTRYPOINT ["cwskimmer-entrypoint.sh"]
CMD ["/usr/bin/supervisord"]

