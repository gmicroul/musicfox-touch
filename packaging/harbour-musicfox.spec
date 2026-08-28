Name:       harbour-musicfox
Summary:    NetEase Cloud Music player for Sailfish OS
Version:    0.3.0
Release:    17
Group:      Applications/Multimedia
License:    GPLv3
URL:        https://github.com/gmicroul/musicfox-touch
Source0:    %{name}-%{version}.tar.bz2
BuildArch:  %{sfos_arch}

BuildRequires:  pkgconfig(Qt5Core)
BuildRequires:  pkgconfig(Qt5Gui)
BuildRequires:  pkgconfig(Qt5Qml)
BuildRequires:  pkgconfig(Qt5Quick)
BuildRequires:  pkgconfig(Qt5Network)
BuildRequires:  pkgconfig(Qt5Multimedia)
BuildRequires:  pkgconfig(Qt5DBus)
BuildRequires:  pkgconfig(sailfishsilica)
BuildRequires:  libsailfishapp-devel
BuildRequires:  mpris-qt5

Requires:   qt5-qtmultimedia-plugin-audio-pulseaudio
Requires:   qt5-qtmultimedia-plugin-resourcepolicy-resourceqt
Requires:   mpris-qt5

%description
A touch-friendly music player for Sailfish OS powered by NetEase Cloud Music.
Features: search songs, top charts, playlists, playback with cover art,
synced lyrics, and lock-screen controls with cover art.

%prep
%setup -q -n %{name}-%{version}

%build
cd app
%qmake5 harbour-musicfox.pro
make %{?_smp_mflags}

%install
rm -rf %{buildroot}
install -D -m 0755 app/harbour-musicfox %{buildroot}/usr/bin/harbour-musicfox
install -D -m 0755 daemon/musicfox-daemon %{buildroot}/usr/libexec/musicfox-daemon
install -D -m 0644 harbour-musicfox.desktop %{buildroot}/usr/share/applications/harbour-musicfox.desktop
install -D -m 0644 app/qml/kitty-dark.png %{buildroot}/usr/share/icons/hicolor/128x128/apps/harbour-musicfox.png
install -D -m 0644 DISCLAIMER.md %{buildroot}/usr/share/doc/harbour-musicfox/DISCLAIMER.md

%files
%defattr(-,root,root,-)
/usr/bin/harbour-musicfox
/usr/libexec/musicfox-daemon
/usr/share/applications/harbour-musicfox.desktop
/usr/share/icons/hicolor/128x128/apps/harbour-musicfox.png
/usr/share/doc/harbour-musicfox/DISCLAIMER.md
