#ifndef PULSELEVELS_H
#define PULSELEVELS_H

#include <QElapsedTimer>
#include <QMap>
#include <QObject>
#include <QProcess>
#include <QTimer>

// Grabs system playback PCM via `parec` monitor sources (no libpulse
// headers needed) and splits it into low / mid / high band energies
// (0..1) for driving the trigram-bar visualizer.
// Falls back to silent zeros if parec is unavailable.
class PulseLevels : public QObject
{
    Q_OBJECT
    Q_PROPERTY(double lowLevel READ lowLevel NOTIFY levelsChanged)
    Q_PROPERTY(double midLevel READ midLevel NOTIFY levelsChanged)
    Q_PROPERTY(double highLevel READ highLevel NOTIFY levelsChanged)
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)

public:
    explicit PulseLevels(QObject *parent = nullptr);
    ~PulseLevels();

    double lowLevel() const { return m_low; }
    double midLevel() const { return m_mid; }
    double highLevel() const { return m_high; }
    bool active() const { return m_active; }

public slots:
    void start();
    void stop();

signals:
    void levelsChanged();
    void activeChanged();

private slots:
    void refreshMonitors();
    void onPollFinished(int code, QProcess::ExitStatus status);
    void onReadyRead();
    void onProcFinished(int code, QProcess::ExitStatus status);
    void onIdleTick();

private:
    struct Biquad {
        double b0 = 0, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
        double x1 = 0, x2 = 0, y1 = 0, y2 = 0;   // stage 1
        double u1 = 0, u2 = 0, v1 = 0, v2 = 0;   // stage 2 (cascade)
        void bandpass(double f0, double q, double fs);
        double step(double x);
    };

    void setActive(bool on);
    Biquad m_fLo, m_fMid, m_fHi;
    double m_envLo = 0, m_envMid = 0, m_envHi = 0;
    double m_peakLo = 0.2, m_peakMid = 0.2, m_peakHi = 0.2;
    double m_low = 0, m_mid = 0, m_high = 0;
    bool m_active = false;

    QList<QProcess *> m_procs;
    QMap<QProcess *, QByteArray> m_bufs;
    QMap<QProcess *, QString> m_src;
    QProcess *m_poll = nullptr;
    QTimer m_pollTimer;
    void spawnParec(const QString &src);
    QElapsedTimer m_emitClock;
    QTimer m_idleTimer;
    QElapsedTimer m_dataClock;
};

#endif // PULSELEVELS_H
