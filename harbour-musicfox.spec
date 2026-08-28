Name:       harbour-musicfox
Summary:    Music player with NetEase Cloud Music
Version:    0.1.0
Release:    1
License:    GPLv3
URL:        https://github.com/user/musicfox-touch
Source0:    %{name}-%{version}.tar.bz2
Requires:   qt5-qtmultimedia-plugin-audio-pulseaudio
Requires:   mapplauncherd

%description
A touch-friendly music player for Sailfish OS powered by NetEase Cloud Music.

%prep
%setup -q -n %{name}-%{version}

%build
# Build daemon
cd daemon
%{_bindir}/go build -o %{_builddir}/%{name}-%{version}/musicfox-daemon .
cd ..

# Build app
cd app
%qmake5 harbour-musicfox.pro
make %{?_smp_mflags}

%install
rm -rf %{buildroot}

# Binary
install -D -m 0755 app/harbour-musicfox %{buildroot}/usr/bin/harbour-musicfox

# Daemon
install -D -m 0755 musicfox-daemon %{buildroot}/usr/libexec/musicfox-daemon

# Desktop file
install -D -m 0644 rpm/harbour-musicfox.desktop %{buildroot}/usr/share/applications/harbour-musicfox.desktop

# Icon
install -D -m 0644 app/qml/kitty-dark.png %{buildroot}/usr/share/icons/hicolor/128x128/apps/harbour-musicfox.png

%files
%defattr(-,root,root,-)
/usr/bin/harbour-musicfox
/usr/libexec/musicfox-daemon
/usr/share/applications/harbour-musicfox.desktop
/usr/share/icons/hicolor/128x128/apps/harbour-musicfox.png
