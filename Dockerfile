FROM debian:bookworm AS wine

# Install Wine, XFCE, network audio stuff
ENV HOME /root
ENV DEBIAN_FRONTEND noninteractive
ENV LC_ALL C.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
RUN dpkg --add-architecture i386
RUN apt-get update && apt-get -y install vim cabextract xvfb novnc x11vnc xdotool wget tar dbus-x11 supervisor net-tools gnupg2 procps wine xfce4 innoextract unzip fonts-liberation fonts-dejavu-core
# Contrib enable
#RUN sed -r -i 's/^deb(.*)$/deb\1 contrib/g' /etc/apt/sources.list
#RUN apt-get -qqy autoclean && rm -rf /tmp/* /var/tmp/*
ENV DISPLAY :0

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

ENV V_SKIMMER 2.1
ENV V_SKIMMERSRV 1.6
ENV V_RBNAGGREGATOR 6.7

# Copy installation files and extract them
ADD install /install
WORKDIR /skimmer_1.9
RUN  unzip /install/Skimmer_1.9/CwSkimmer.zip && innoextract Setup.exe
WORKDIR /skimmer_${V_SKIMMER}
RUN unzip /install/Skimmer_${V_SKIMMER}/CwSkimmer.zip && innoextract Setup.exe
WORKDIR /skimmersrv_${V_SKIMMERSRV}
RUN unzip /install/SkimmerSrv_${V_SKIMMERSRV}/SkimSrv.zip && innoextract Setup.exe

# Download and install RBN Aggregator v6.7
WORKDIR /rbnaggregator_${V_RBNAGGREGATOR}
RUN wget -O "Aggregator v${V_RBNAGGREGATOR}.exe" "https://cms.reversebeacon.net/sites/cms.reversebeacon.net/files/2025/02/21/Aggregator%20v6.7.exe"

# Download and install ka9q_ubersdr CW_Skimmer driver
WORKDIR /ubersdr_driver
RUN wget https://github.com/madpsy/ka9q_ubersdr/releases/download/latest/CW_Skimmer.zip
RUN unzip CW_Skimmer.zip

# Add late installer
ADD ./install.sh /install

WORKDIR /root/

FROM installation as config
# FIXME: config vars here -e RIGSERVER=10.101.1.53 -e RIGSERVER_CAT_PORT=1234 -e RIGSERVER_PTT_PORT=4321 

# XFCE config
ADD ./config/xfce4 /root/.config/xfce4
# Add startup stuff
ADD ./config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
ADD ./config/startup.sh /bin
ADD ./config/startup_sound.sh /bin

# Configuration stuff
ENV PATH_INI_SKIMSRV "/root/.wine/drive_c/users/root/AppData/Roaming/Afreet/Products/SkimSrv/SkimSrv.ini"
ENV PATH_INI_AGGREGATOR "/rbnaggregator_${V_RBNAGGREGATOR}/Aggregator.ini"
ENV PATH_INI_UBERSDR "/skimmersrv_${V_SKIMMERSRV}/app/UberSDRIntf.ini"
RUN mkdir -p $(dirname ${PATH_INI_SKIMSRV})
COPY ./config/rbn/Aggregator.ini ${PATH_INI_AGGREGATOR}
COPY ./config/skimsrv/SkimSrv.ini ${PATH_INI_SKIMSRV}
RUN cp /ubersdr_driver/* /skimmersrv_${V_SKIMMERSRV}/app/
RUN rm -f /skimmersrv_${V_SKIMMERSRV}/app/Qs1rIntf.dll
COPY ./install/patt3ch/patt3ch.lst /skimmersrv_${V_SKIMMERSRV}/userappdata/Afreet/Reference/Patt3Ch.lst

ENV LOGFILE_UBERSDR /root/ubersdr_driver_log_file.txt
ENV LOGIFLE_AGGREGATOR /root/AggregatorLog.txt

## Configuration
ENV QTH KA12aa
ENV NAME "Mr. X"
ENV SQUARE KA12aa
ENV UBERSDR_HOST ka9q_ubersdr
ENV UBERSDR_PORT 8080

EXPOSE 7373
EXPOSE 7300
EXPOSE 7550

ENTRYPOINT ["startup.sh"]
CMD ["/usr/bin/supervisord"]

