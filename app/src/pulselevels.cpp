#include "pulselevels.h"

#include <QtEndian>
#include <QtMath>
#include <QDebug>

namespace {
const int kRate = 48000;
const double kGain = 10.0;
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
    m_fLo.bandpass(100.0, 1.5, kRate);
    m_fMid.bandpass(1000.0, 1.4, kRate);
    m_fHi.bandpass(6000.0, 1.2, kRate);
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
    if (!m_procs.isEmpty()) return;
    static const char *kSources[] = {
        "sink.primary_output.monitor",
        "sink.deep_buffer.monitor",
    };
    for (const char *src : kSources) {
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
            continue;
        }
        m_procs.append(p);
        m_bufs.insert(p, QByteArray());
    }
    setActive(!m_procs.isEmpty());
}

void PulseLevels::stop()
{
    for (QProcess *p : m_procs) {
        p->kill();
        p->deleteLater();
    }
    m_procs.clear();
    m_bufs.clear();
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
        const double egl = m_envLo * kGain;
        const double egm = m_envMid * kGain;
        const double egh = m_envHi * kGain;
        m_peakLo = qMax(egl, m_peakLo * 0.995);
        m_peakMid = qMax(egm, m_peakMid * 0.995);
        m_peakHi = qMax(egh, m_peakHi * 0.995);
        const double ref = qMax(0.3, qMax(m_peakLo, qMax(m_peakMid, m_peakHi)));
        const double nl = egl < 0.12 ? 0.0 : qMin(1.0, egl / ref);
        const double nm = egm < 0.12 ? 0.0 : qMin(1.0, egm / ref);
        const double nh = egh < 0.12 ? 0.0 : qMin(1.0, egh / ref);
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
    if (!p) return;
    m_procs.removeAll(p);
    m_bufs.remove(p);
    p->deleteLater();
    if (m_procs.isEmpty()) {
        setActive(false);
        // monitor may come back (e.g. pulse restarted): retry shortly
        QTimer::singleShot(3000, this, [this]() {
            if (m_procs.isEmpty()) start();
        });
    }
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
