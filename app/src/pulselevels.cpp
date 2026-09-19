#include "pulselevels.h"

#include <QtEndian>
#include <QtMath>
#include <QDebug>

namespace {
const int kRate = 48000;
// Display gains: vocals live mostly in mid; dim it so climaxes don't
// blind while lows/highs stay punchy. Dynamics are preserved (scaling,
// not capping).
const double kDispLo = 1.0;
const double kDispMid = 0.65;
const double kDispHi = 1.0;
const int kEmitMs = 66;     // ~15 Hz UI updates
const int kIdleMs = 400;    // no data for this long -> decay to zero
}

void PulseLevels::Biquad::bandpass(double f0, double q, double fs)
{
    // RBJ band-pass (constant 0 dB peak gain).
    const double w0 = 2.0 * M_PI * f0 / fs;
    const double alpha = qSin(w0) / (2.0 * q);
    const double a0 = 1.0 + alpha;
    b0 = alpha / a0;
    b1 = 0.0;
    b2 = -alpha / a0;
    a1 = -2.0 * qCos(w0) / a0;
    a2 = (1.0 - alpha) / a0;
}

double PulseLevels::Biquad::step(double x)
{
    const double y1o = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1; x1 = x;
    y2 = y1; y1 = y1o;
    const double y2o = b0 * y1o + b1 * u1 + b2 * u2 - a1 * v1 - a2 * v2;
    u2 = u1; u1 = y1o;
    v2 = v1; v1 = y2o;
    return y2o;
}

PulseLevels::PulseLevels(QObject *parent)
    : QObject(parent)
{
    // Effect-first tuning for phone audio (not lab-flat):
    // - low @160Hz catches kick/bass phones can emit (fundamentals + harmonics)
    // - mid @700Hz carries vocals/instruments (display dimmed, see kDispMid)
    // - high @3.5kHz catches vocal brilliance/cymbals so tops dance
    m_fLo.bandpass(160.0, 1.4, kRate);
    m_fMid.bandpass(700.0, 1.0, kRate);
    m_fHi.bandpass(3500.0, 1.0, kRate);
    m_emitClock.start();
    m_dataClock.start();
    connect(&m_idleTimer, &QTimer::timeout, this, &PulseLevels::onIdleTick);
    m_idleTimer.setInterval(120);
    m_idleTimer.start();
    start();
}

PulseLevels::~PulseLevels()
{
    stop();
}

void PulseLevels::start()
{
    if (!m_poll) {
        m_poll = new QProcess(this);
        connect(m_poll, SIGNAL(finished(int, QProcess::ExitStatus)),
                this, SLOT(onPollFinished(int, QProcess::ExitStatus)));
        connect(&m_pollTimer, &QTimer::timeout,
                this, &PulseLevels::refreshMonitors);
        m_pollTimer.setInterval(3000);
    }
    if (!m_pollTimer.isActive())
        m_pollTimer.start();
    refreshMonitors();
}

void PulseLevels::refreshMonitors()
{
    if (!m_poll || m_poll->state() != QProcess::NotRunning) return;
    m_poll->start("pactl", QStringList() << "list" << "sources" << "short");
}

void PulseLevels::onPollFinished(int, QProcess::ExitStatus)
{
    if (!m_poll) return;
    const QByteArray out = m_poll->readAllStandardOutput();
    QSet<QString> running;
    for (QProcess *p : m_procs)
        if (m_src.contains(p)) running.insert(m_src[p]);
    for (const QByteArray &line : out.split('\n')) {
        const QList<QByteArray> cols = line.split('\t');
        if (cols.size() < 2) continue;
        const QString name = QString::fromUtf8(cols[1]).trimmed();
        // Any sink monitor (built-in, deep buffer, bluetooth, ...).
        // Idle ones block harmlessly; bluetooth sinks appear on connect.
        if (!name.startsWith("sink.") || !name.endsWith(".monitor")) continue;
        if (name == "sink.null.monitor") continue;
        if (running.contains(name)) continue;
        spawnParec(name);
        running.insert(name);
    }
}

void PulseLevels::spawnParec(const QString &src)
{
    QProcess *p = new QProcess(this);
    connect(p, &QProcess::readyReadStandardOutput,
            this, &PulseLevels::onReadyRead);
    connect(p, SIGNAL(finished(int, QProcess::ExitStatus)),
            this, SLOT(onProcFinished(int, QProcess::ExitStatus)));
    p->start("parec", QStringList()
             << "-d" << src
             << "--format=s16le"
             << QString("--rate=%1").arg(kRate)
             << "--channels=2");
    if (!p->waitForStarted(1500)) {
        qWarning() << "parec failed for" << src << p->errorString();
        p->deleteLater();
        return;
    }
    m_procs.append(p);
    m_bufs.insert(p, QByteArray());
    m_src.insert(p, src);
    setActive(true);
}

void PulseLevels::stop()
{
    m_pollTimer.stop();
    for (QProcess *p : m_procs) {
        p->kill();
        p->deleteLater();
    }
    m_procs.clear();
    m_bufs.clear();
    m_src.clear();
    setActive(false);
}

void PulseLevels::setActive(bool on)
{
    if (on == m_active) return;
    m_active = on;
    emit activeChanged();
}

void PulseLevels::onReadyRead()
{
    QProcess *p = qobject_cast<QProcess *>(sender());
    if (!p || !m_bufs.contains(p)) return;
    QByteArray &buf = m_bufs[p];
    buf.append(p->readAllStandardOutput());
    // consume whole stereo frames (L+R int16LE)
    const int frames = buf.size() / 4;
    if (frames <= 0) return;
    const char *d = buf.constData();
    for (int i = 0; i < frames; ++i) {
        const qint16 l = qFromLittleEndian<qint16>(reinterpret_cast<const uchar *>(d + i * 4));
        const qint16 r = qFromLittleEndian<qint16>(reinterpret_cast<const uchar *>(d + i * 4 + 2));
        const double x = (double(l) + double(r)) / 65536.0;
        const double yl = m_fLo.step(x);
        const double ym = m_fMid.step(x);
        const double yh = m_fHi.step(x);
        const double al = qAbs(yl), am = qAbs(ym), ah = qAbs(yh);
        m_envLo += (al - m_envLo) * (al > m_envLo ? 0.40 : 0.05);
        m_envMid += (am - m_envMid) * (am > m_envMid ? 0.40 : 0.05);
        m_envHi += (ah - m_envHi) * (ah > m_envHi ? 0.40 : 0.05);
    }
    buf.remove(0, frames * 4);
    m_dataClock.restart();
    if (m_emitClock.elapsed() >= kEmitMs) {
        m_emitClock.restart();
        // AGC: shared peak reference keeps inter-band balance while
        // following the song's own dynamics (quiet passages still dance).
        const double egl = m_envLo * 10.0;
        const double egm = m_envMid * 10.0;
        const double egh = m_envHi * 10.0;
        m_peakLo = qMax(egl, m_peakLo * 0.995);
        m_peakMid = qMax(egm, m_peakMid * 0.995);
        m_peakHi = qMax(egh, m_peakHi * 0.995);
        const double ref = qMax(0.3, qMax(m_peakLo, qMax(m_peakMid, m_peakHi)));
        const double nl = (egl < 0.12 ? 0.0 : qMin(1.0, egl / ref)) * kDispLo;
        const double nm = (egm < 0.12 ? 0.0 : qMin(1.0, egm / ref)) * kDispMid;
        const double nh = (egh < 0.12 ? 0.0 : qMin(1.0, egh / ref)) * kDispHi;
        if (!qFuzzyCompare(nl + 1, m_low + 1) ||
            !qFuzzyCompare(nm + 1, m_mid + 1) ||
            !qFuzzyCompare(nh + 1, m_high + 1)) {
            m_low = nl; m_mid = nm; m_high = nh;
            emit levelsChanged();
        }
    }
}

void PulseLevels::onProcFinished(int, QProcess::ExitStatus)
{
    QProcess *p = qobject_cast<QProcess *>(sender());
    if (!p || p == m_poll) return;
    m_procs.removeAll(p);
    m_bufs.remove(p);
    m_src.remove(p);
    p->deleteLater();
    if (m_procs.isEmpty()) setActive(false);
    // The poll timer respawns it if the source still exists.
}

void PulseLevels::onIdleTick()
{
    if (m_dataClock.elapsed() < kIdleMs) return;
    if (m_low <= 0.001 && m_mid <= 0.001 && m_high <= 0.001) return;
    m_envLo *= 0.8; m_envMid *= 0.8; m_envHi *= 0.8;
    m_peakLo *= 0.9; m_peakMid *= 0.9; m_peakHi *= 0.9;
    m_low *= 0.8; m_mid *= 0.8; m_high *= 0.8;
    emit levelsChanged();
}
