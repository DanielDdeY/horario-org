import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react'
import { useAuth } from '../../app/auth/useAuth'
import {
  getCourses,
  getNotices,
  getTeacherProfile,
  proposeCourseSchedule,
  updateAvailability,
  type AvailabilitySlot,
  type Course,
  type Notice,
  type TeacherProfile,
} from '../../api/horarioApi'
import { getCourseLabel } from './courseLabel'
import { parseAvailabilitySlots, type AvailabilityDraft } from './availability'
import { formatMinutes } from './time'

interface DashboardData {
  profile: TeacherProfile
  courses: Course[]
  notices: Notice[]
}

const dayNames = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo']

function asDrafts(slots: AvailabilitySlot[] | null): AvailabilityDraft[] {
  return (slots ?? []).map((slot) => ({
    day: String(slot.dia),
    start: formatMinutes(slot.inicioMin),
    end: formatMinutes(slot.finMin),
  }))
}

function formatSlot(slot: AvailabilitySlot): string {
  return `${dayNames[slot.dia - 1]} · ${formatMinutes(slot.inicioMin)}–${formatMinutes(slot.finMin)}`
}

export function TeacherDashboard() {
  const { session, logout } = useAuth()
  const teacherId = session?.profesorId
  const [profile, setProfile] = useState<TeacherProfile | null>(null)
  const [courses, setCourses] = useState<Course[]>([])
  const [notices, setNotices] = useState<Notice[]>([])
  const [drafts, setDrafts] = useState<AvailabilityDraft[]>([])
  const [periodId, setPeriodId] = useState('')
  const [courseId, setCourseId] = useState('')
  const [proposalSlot, setProposalSlot] = useState<AvailabilityDraft>({ day: '1', start: '', end: '' })
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [pageError, setPageError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)

  const loadData = useCallback(async () => {
    if (teacherId === null || teacherId === undefined) {
      throw new Error('La sesión no contiene el identificador del profesor.')
    }
    const [profile, courses, notices] = await Promise.all([
      getTeacherProfile(teacherId),
      getCourses(),
      getNotices(),
    ])
    return { profile, courses, notices }
  }, [teacherId])

  const applyData = useCallback(({ profile: nextProfile, courses: nextCourses, notices: nextNotices }: DashboardData) => {
    setProfile(nextProfile)
    setCourses(nextCourses)
    setNotices(nextNotices)
    setDrafts(asDrafts(nextProfile.disponibilidad))
    setPeriodId(nextProfile.periodoId === null ? '' : String(nextProfile.periodoId))
  }, [])

  useEffect(() => {
    let active = true

    loadData()
      .then((data) => {
        if (active) applyData(data)
      })
      .catch((cause: unknown) => {
        if (active) setPageError(cause instanceof Error ? cause.message : 'No se pudo cargar el perfil.')
      })
      .finally(() => {
        if (active) setLoading(false)
      })

    return () => {
      active = false
    }
  }, [applyData, loadData])

  const aptCourses = useMemo(() => {
    if (!profile) return []
    return profile.cursosAptos.map((id) => courses.find((course) => course.id === id) ?? {
      id,
      codigo: `Curso ${id}`,
      nombre: 'Información no disponible',
      categoriaId: profile.categoriaId,
    })
  }, [courses, profile])

  function updateDraft(index: number, patch: Partial<AvailabilityDraft>) {
    setDrafts((current) => current.map((slot, slotIndex) =>
      slotIndex === index ? { ...slot, ...patch } : slot,
    ))
  }

  async function handleSaveAvailability(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setMessage(null)
    setPageError(null)

    const parsedPeriod = Number(periodId)
    if (!Number.isInteger(parsedPeriod) || parsedPeriod < 1) {
      setPageError('Ingresa un período válido antes de guardar.')
      return
    }

    let availability: AvailabilitySlot[]
    try {
      availability = parseAvailabilitySlots(drafts)
    } catch (cause) {
      setPageError(cause instanceof Error ? cause.message : 'Revisa los intervalos.')
      return
    }

    if (teacherId === null || teacherId === undefined) return
    setSaving(true)
    try {
      const updated = await updateAvailability(teacherId, parsedPeriod, availability)
      setProfile(updated)
      setDrafts(asDrafts(updated.disponibilidad))
      setNotices((current) => [...updated.avisosGenerados, ...current])
      setMessage('Tu disponibilidad se guardó correctamente.')
    } catch (cause) {
      setPageError(cause instanceof Error ? cause.message : 'No se pudo guardar la disponibilidad.')
    } finally {
      setSaving(false)
    }
  }

  async function handleProposal(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setMessage(null)
    setPageError(null)

    const parsedPeriod = Number(periodId)
    const parsedCourse = Number(courseId)
    if (!Number.isInteger(parsedPeriod) || parsedPeriod < 1 || !Number.isInteger(parsedCourse) || parsedCourse < 1) {
      setPageError('Selecciona un curso e ingresa un período válido.')
      return
    }

    let franjas: AvailabilitySlot[]
    try {
      franjas = parseAvailabilitySlots([proposalSlot])
    } catch (cause) {
      setPageError(cause instanceof Error ? cause.message : 'Revisa la franja propuesta.')
      return
    }

    if (teacherId === null || teacherId === undefined) return
    setSaving(true)
    try {
      await proposeCourseSchedule(teacherId, {
        cursoId: parsedCourse,
        periodoId: parsedPeriod,
        franjas,
      })
      applyData(await loadData())
      setMessage('Tu propuesta se envió al coordinador para su aprobación.')
    } catch (cause) {
      setPageError(cause instanceof Error ? cause.message : 'No se pudo enviar la propuesta.')
    } finally {
      setSaving(false)
    }
  }

  if (loading) {
    return <main className="page-shell"><p className="loading-state">Cargando tu información…</p></main>
  }

  return (
    <div className="page-shell">
      <header className="topbar">
        <a className="wordmark" href="/" aria-label="Horario, inicio">
          <span className="brand-mark brand-mark-small" aria-hidden="true">H</span>
          <span>horario<span className="wordmark-dot">.</span></span>
        </a>
        <div className="topbar-user">
          <span className="user-role">Profesor</span>
          <span className="user-name">{profile?.nombre ?? 'Mi cuenta'}</span>
          <button className="button button-quiet" onClick={logout} type="button">Cerrar sesión</button>
        </div>
      </header>

      <main className="dashboard">
        <section className="welcome-row">
          <div>
            <p className="eyebrow">PORTAL DOCENTE</p>
            <h1>Hola, {profile?.nombre ?? 'profesor'}.</h1>
            <p className="muted">Administra tus horarios disponibles y mantén tus datos al día.</p>
          </div>
          {profile?.periodoId && <span className="period-pill">Período {profile.periodoId}</span>}
        </section>

        {pageError && <p className="message message-error" role="alert">{pageError}</p>}
        {message && <p className="message message-success" role="status">{message}</p>}

        <section className="content-grid">
          <article className="panel availability-panel">
            <div className="panel-heading">
              <div>
                <p className="eyebrow">TU AGENDA</p>
                <h2>Mi disponibilidad</h2>
                <p className="muted">Indica las franjas en las que puedes dictar clases.</p>
              </div>
              <span className="panel-icon" aria-hidden="true">◷</span>
            </div>

            <form onSubmit={handleSaveAvailability}>
              <label className="period-field">
                Período académico
                <input
                  inputMode="numeric"
                  min="1"
                  onChange={(event) => setPeriodId(event.target.value)}
                  placeholder="Ej. 20261"
                  required
                  type="number"
                  value={periodId}
                />
              </label>
              <div className="slots-list">
                {drafts.length === 0 && (
                  <p className="empty-note">Aún no tienes franjas registradas. Añade la primera para empezar.</p>
                )}
                {drafts.map((slot, index) => (
                  <div className="slot-row" key={`availability-${index}`}>
                    <label className="day-field">
                      <span className="visually-hidden">Día del intervalo {index + 1}</span>
                      <select
                        aria-label={`Día del intervalo ${index + 1}`}
                        onChange={(event) => updateDraft(index, { day: event.target.value })}
                        value={slot.day}
                      >
                        {dayNames.map((day, dayIndex) => (
                          <option key={day} value={dayIndex + 1}>{day}</option>
                        ))}
                      </select>
                    </label>
                    <label className="time-field">
                      <span className="visually-hidden">Desde</span>
                      <input
                        aria-label={`Hora de inicio del intervalo ${index + 1}`}
                        onChange={(event) => updateDraft(index, { start: event.target.value })}
                        placeholder="08:00"
                        required
                        value={slot.start}
                      />
                    </label>
                    <span className="time-separator">a</span>
                    <label className="time-field">
                      <span className="visually-hidden">Hasta</span>
                      <input
                        aria-label={`Hora de fin del intervalo ${index + 1}`}
                        onChange={(event) => updateDraft(index, { end: event.target.value })}
                        placeholder="12:00"
                        required
                        value={slot.end}
                      />
                    </label>
                    <button
                      aria-label={`Eliminar intervalo ${index + 1}`}
                      className="icon-button"
                      onClick={() => setDrafts((current) => current.filter((_, slotIndex) => slotIndex !== index))}
                      type="button"
                    >×</button>
                  </div>
                ))}
              </div>
              <div className="form-actions">
                <button
                  className="button button-secondary"
                  onClick={() => setDrafts((current) => [...current, { day: '1', start: '08:00', end: '12:00' }])}
                  type="button"
                >+ Añadir franja</button>
                <button className="button button-primary" disabled={saving} type="submit">
                  {saving ? 'Guardando…' : 'Guardar disponibilidad'}
                </button>
              </div>
              <p className="helper-text">Formato 24 horas. La hora final puede ser 24:00.</p>
            </form>
          </article>

          <article className="panel courses-panel">
            <div className="panel-heading">
              <div>
                <p className="eyebrow">TU PERFIL</p>
                <h2>Mis cursos aptos</h2>
                <p className="muted">Cursos habilitados por el coordinador.</p>
              </div>
              <span className="count-badge">{aptCourses.length}</span>
            </div>
            {aptCourses.length ? (
              <ul className="course-list">
                {aptCourses.map((course) => (
                  <li key={course.id}>
                    <span className="course-code">{course.codigo === 'string' ? `#${course.id}` : course.codigo}</span>
                    <span>{course.nombre === 'string' ? `Curso #${course.id} (Mock)` : course.nombre}</span>
                  </li>
                ))}
              </ul>
            ) : <p className="empty-note">Todavía no tienes cursos habilitados.</p>}
          </article>
        </section>

        <section className="content-grid lower-grid">
          <article className="panel">
            <div className="panel-heading">
              <div>
                <p className="eyebrow">SOLICITUDES</p>
                <h2>Mis propuestas</h2>
              </div>
            </div>
            {profile?.propuestas.length ? (
              <ul className="proposal-list">
                {profile.propuestas.map((proposal) => (
                  <li key={proposal.id}>
                    <div className="list-item-title">
                      <strong>Curso {proposal.cursoId}</strong>
                      <span className={`status-pill status-${proposal.estado}`}>{proposal.estado}</span>
                    </div>
                    <p className="muted">{proposal.franjas.map(formatSlot).join(' · ')}</p>
                  </li>
                ))}
              </ul>
            ) : <p className="empty-note">No has enviado propuestas para este período.</p>}
            <form className="proposal-form" onSubmit={handleProposal}>
              <h3>Proponer horario para un curso</h3>
              <label>
                Curso de mi categoría
                <select required value={courseId} onChange={(event) => setCourseId(event.target.value)}>
                  <option value="">Selecciona un curso</option>
                  {courses.map((course) => (
                    <option key={course.id} value={course.id}>{getCourseLabel(course)}</option>
                  ))}
                </select>
              </label>
              <div className="proposal-fields">
                <label>
                  Día
                  <select
                    value={proposalSlot.day}
                    onChange={(event) => setProposalSlot((current) => ({ ...current, day: event.target.value }))}
                  >
                    {dayNames.map((day, index) => <option key={day} value={index + 1}>{day}</option>)}
                  </select>
                </label>
                <label>
                  Desde
                  <input
                    onChange={(event) => setProposalSlot((current) => ({ ...current, start: event.target.value }))}
                    placeholder="08:00"
                    required
                    value={proposalSlot.start}
                  />
                </label>
                <label>
                  Hasta
                  <input
                    onChange={(event) => setProposalSlot((current) => ({ ...current, end: event.target.value }))}
                    placeholder="12:00"
                    required
                    value={proposalSlot.end}
                  />
                </label>
              </div>
              <button className="button button-secondary" disabled={saving || courses.length === 0} type="submit">
                Enviar propuesta
              </button>
            </form>
          </article>

          <article className="panel">
            <div className="panel-heading">
              <div>
                <p className="eyebrow">ACTUALIZACIONES</p>
                <h2>Avisos</h2>
                <p className="muted">Cambios relacionados con tus clases publicadas.</p>
              </div>
              <span className="count-badge">{notices.length}</span>
            </div>
            {notices.length ? (
              <ul className="notice-list">
                {notices.map((notice, index) => (
                  <li key={notice.id ?? `${notice.horarioId}-${notice.sesionId}-${index}`}>
                    <span className="notice-dot" aria-hidden="true" />
                    <div>
                      <strong>Sesión {notice.sesionId}</strong>
                      <p className="muted">
                        {dayNames[notice.dia - 1]} · {formatMinutes(notice.inicioMin)}
                        {notice.creadoEn ? ` · ${new Date(notice.creadoEn).toLocaleDateString()}` : ''}
                      </p>
                    </div>
                  </li>
                ))}
              </ul>
            ) : <p className="empty-note">No tienes avisos nuevos.</p>}
          </article>
        </section>
      </main>
    </div>
  )
}
