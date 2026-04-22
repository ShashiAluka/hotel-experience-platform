import { useState, useEffect } from 'react'
import {
  AreaChart, Area, BarChart, Bar, XAxis, YAxis,
  CartesianGrid, Tooltip, ResponsiveContainer, Cell
} from 'recharts'

const API = import.meta.env.VITE_API_URL ?? ''

interface Stats {
  totalReservations: number
  confirmedToday: number
  currentOccupancy: number
  revenue30d: number
}

interface OccupancyPoint { date: string; occupancy: number; revenue: number }
interface RecentReservation {
  id: string; guestName: string; hotelId: string
  checkInDate: string; checkOutDate: string
  status: string; totalAmount: number
}

const STATUS_COLORS: Record<string, string> = {
  CONFIRMED: '#22c55e', PENDING: '#f59e0b',
  CANCELLED: '#ef4444', CHECKED_IN: '#3b82f6', CHECKED_OUT: '#8b5cf6',
}

const fmt = (n: number) => new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 }).format(n)

export default function Dashboard() {
  const [stats, setStats] = useState<Stats | null>(null)
  const [occupancy, setOccupancy] = useState<OccupancyPoint[]>([])
  const [reservations, setReservations] = useState<RecentReservation[]>([])
  const [loading, setLoading] = useState(true)
  const [activeFilter, setActiveFilter] = useState<string>('ALL')

  useEffect(() => {
    async function load() {
      try {
        // In a real deployment these hit API Gateway
        const [statsRes, occupancyRes, recentRes] = await Promise.all([
          fetch(`${API}/api/v1/analytics/stats`).then(r => r.json()).catch(() => mockStats),
          fetch(`${API}/api/v1/analytics/occupancy`).then(r => r.json()).catch(() => mockOccupancy),
          fetch(`${API}/api/v1/reservations?size=10`).then(r => r.json()).catch(() => ({ content: mockReservations })),
        ])
        setStats(statsRes)
        setOccupancy(occupancyRes)
        setReservations(recentRes.content ?? recentRes)
      } finally {
        setLoading(false)
      }
    }
    load()
  }, [])

  const filtered = activeFilter === 'ALL'
    ? reservations
    : reservations.filter(r => r.status === activeFilter)

  if (loading) return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100vh', fontFamily: 'system-ui' }}>
      <p style={{ color: '#6b7280' }}>Loading dashboard…</p>
    </div>
  )

  return (
    <div style={{ fontFamily: "'Inter', system-ui, sans-serif", background: '#f8fafc', minHeight: '100vh', padding: '0' }}>
      {/* Header */}
      <header style={{ background: '#0f172a', color: 'white', padding: '16px 32px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <div>
          <h1 style={{ margin: 0, fontSize: '20px', fontWeight: 600, letterSpacing: '-0.01em' }}>Hotel Experience Platform</h1>
          <p style={{ margin: 0, fontSize: '13px', color: '#94a3b8', marginTop: '2px' }}>Operations Dashboard</p>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
          <span style={{ width: '8px', height: '8px', borderRadius: '50%', background: '#22c55e', display: 'inline-block' }} />
          <span style={{ fontSize: '13px', color: '#94a3b8' }}>Live</span>
        </div>
      </header>

      <main style={{ padding: '24px 32px', maxWidth: '1400px', margin: '0 auto' }}>
        {/* Stats row */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '16px', marginBottom: '24px' }}>
          {[
            { label: 'Total Reservations', value: stats?.totalReservations.toLocaleString() ?? '—', color: '#3b82f6' },
            { label: 'Confirmed Today',    value: stats?.confirmedToday.toLocaleString() ?? '—',    color: '#22c55e' },
            { label: 'Current Occupancy',  value: `${stats?.currentOccupancy ?? '—'}%`,             color: '#f59e0b' },
            { label: '30-Day Revenue',     value: stats ? fmt(stats.revenue30d) : '—',              color: '#8b5cf6' },
          ].map(({ label, value, color }) => (
            <div key={label} style={{ background: 'white', borderRadius: '12px', padding: '20px', border: '1px solid #e2e8f0' }}>
              <p style={{ margin: '0 0 8px', fontSize: '12px', color: '#64748b', textTransform: 'uppercase', letterSpacing: '0.06em', fontWeight: 500 }}>{label}</p>
              <p style={{ margin: 0, fontSize: '28px', fontWeight: 700, color }}>{value}</p>
            </div>
          ))}
        </div>

        {/* Charts row */}
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px', marginBottom: '24px' }}>
          <div style={{ background: 'white', borderRadius: '12px', padding: '20px', border: '1px solid #e2e8f0' }}>
            <h3 style={{ margin: '0 0 16px', fontSize: '14px', fontWeight: 600, color: '#0f172a' }}>Occupancy Rate (30 days)</h3>
            <ResponsiveContainer width="100%" height={200}>
              <AreaChart data={occupancy}>
                <defs>
                  <linearGradient id="occGrad" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor="#3b82f6" stopOpacity={0.15}/>
                    <stop offset="95%" stopColor="#3b82f6" stopOpacity={0}/>
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
                <XAxis dataKey="date" tick={{ fontSize: 11, fill: '#94a3b8' }} tickLine={false} />
                <YAxis tick={{ fontSize: 11, fill: '#94a3b8' }} tickLine={false} axisLine={false} unit="%" />
                <Tooltip formatter={(v: number) => [`${v}%`, 'Occupancy']} />
                <Area type="monotone" dataKey="occupancy" stroke="#3b82f6" strokeWidth={2} fill="url(#occGrad)" />
              </AreaChart>
            </ResponsiveContainer>
          </div>

          <div style={{ background: 'white', borderRadius: '12px', padding: '20px', border: '1px solid #e2e8f0' }}>
            <h3 style={{ margin: '0 0 16px', fontSize: '14px', fontWeight: 600, color: '#0f172a' }}>Daily Revenue (30 days)</h3>
            <ResponsiveContainer width="100%" height={200}>
              <BarChart data={occupancy}>
                <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
                <XAxis dataKey="date" tick={{ fontSize: 11, fill: '#94a3b8' }} tickLine={false} />
                <YAxis tick={{ fontSize: 11, fill: '#94a3b8' }} tickLine={false} axisLine={false} tickFormatter={(v) => `$${(v/1000).toFixed(0)}k`} />
                <Tooltip formatter={(v: number) => [fmt(v), 'Revenue']} />
                <Bar dataKey="revenue" radius={[3, 3, 0, 0]}>
                  {occupancy.map((_, i) => <Cell key={i} fill={i === occupancy.length - 1 ? '#3b82f6' : '#bfdbfe'} />)}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>

        {/* Reservations table */}
        <div style={{ background: 'white', borderRadius: '12px', border: '1px solid #e2e8f0', overflow: 'hidden' }}>
          <div style={{ padding: '16px 20px', borderBottom: '1px solid #f1f5f9', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            <h3 style={{ margin: 0, fontSize: '14px', fontWeight: 600, color: '#0f172a' }}>Recent Reservations</h3>
            <div style={{ display: 'flex', gap: '6px' }}>
              {['ALL', 'CONFIRMED', 'PENDING', 'CHECKED_IN', 'CANCELLED'].map(f => (
                <button key={f} onClick={() => setActiveFilter(f)} style={{
                  padding: '4px 10px', fontSize: '12px', borderRadius: '6px', cursor: 'pointer', border: 'none',
                  background: activeFilter === f ? '#0f172a' : '#f1f5f9',
                  color: activeFilter === f ? 'white' : '#64748b', fontWeight: activeFilter === f ? 600 : 400,
                }}>
                  {f === 'ALL' ? 'All' : f.replace('_', ' ')}
                </button>
              ))}
            </div>
          </div>
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '13px' }}>
            <thead>
              <tr style={{ background: '#f8fafc' }}>
                {['ID', 'Guest', 'Hotel', 'Check-in', 'Check-out', 'Amount', 'Status'].map(h => (
                  <th key={h} style={{ padding: '10px 16px', textAlign: 'left', fontSize: '11px', fontWeight: 600, color: '#64748b', textTransform: 'uppercase', letterSpacing: '0.05em' }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {filtered.map((r, i) => (
                <tr key={r.id} style={{ borderTop: '1px solid #f1f5f9', background: i % 2 === 0 ? 'white' : '#fafafa' }}>
                  <td style={{ padding: '12px 16px', fontFamily: 'monospace', color: '#64748b' }}>{r.id.slice(0, 8).toUpperCase()}</td>
                  <td style={{ padding: '12px 16px', fontWeight: 500, color: '#0f172a' }}>{r.guestName}</td>
                  <td style={{ padding: '12px 16px', color: '#475569' }}>{r.hotelId}</td>
                  <td style={{ padding: '12px 16px', color: '#475569' }}>{r.checkInDate}</td>
                  <td style={{ padding: '12px 16px', color: '#475569' }}>{r.checkOutDate}</td>
                  <td style={{ padding: '12px 16px', fontWeight: 500, color: '#0f172a' }}>{fmt(r.totalAmount)}</td>
                  <td style={{ padding: '12px 16px' }}>
                    <span style={{
                      padding: '3px 10px', borderRadius: '20px', fontSize: '11px', fontWeight: 600,
                      background: STATUS_COLORS[r.status] + '20', color: STATUS_COLORS[r.status],
                    }}>
                      {r.status.replace('_', ' ')}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </main>
    </div>
  )
}

// Mock data for local dev / demo
const mockStats: Stats = { totalReservations: 4821, confirmedToday: 47, currentOccupancy: 73, revenue30d: 284600 }
const mockOccupancy: OccupancyPoint[] = Array.from({ length: 30 }, (_, i) => ({
  date: new Date(Date.now() - (29 - i) * 86400000).toLocaleDateString('en-US', { month: 'short', day: 'numeric' }),
  occupancy: Math.round(60 + Math.random() * 30),
  revenue: Math.round(7000 + Math.random() * 5000),
}))
const mockReservations: RecentReservation[] = [
  { id: 'a1b2c3d4-e5f6', guestName: 'Emily Chen',      hotelId: 'HYT-CHI-001', checkInDate: '2024-02-10', checkOutDate: '2024-02-13', status: 'CONFIRMED',   totalAmount: 780 },
  { id: 'b2c3d4e5-f6a1', guestName: 'Marcus Williams', hotelId: 'HYT-NYC-002', checkInDate: '2024-02-11', checkOutDate: '2024-02-12', status: 'CHECKED_IN',  totalAmount: 340 },
  { id: 'c3d4e5f6-a1b2', guestName: 'Sophie Laurent',  hotelId: 'HYT-LAX-003', checkInDate: '2024-02-15', checkOutDate: '2024-02-18', status: 'PENDING',     totalAmount: 1200 },
  { id: 'd4e5f6a1-b2c3', guestName: 'Raj Patel',       hotelId: 'HYT-CHI-001', checkInDate: '2024-01-28', checkOutDate: '2024-01-30', status: 'CHECKED_OUT', totalAmount: 520 },
  { id: 'e5f6a1b2-c3d4', guestName: 'Anna Kowalski',   hotelId: 'HYT-MIA-004', checkInDate: '2024-02-08', checkOutDate: '2024-02-09', status: 'CANCELLED',   totalAmount: 195 },
  { id: 'f6a1b2c3-d4e5', guestName: 'James O\'Brien',  hotelId: 'HYT-NYC-002', checkInDate: '2024-02-20', checkOutDate: '2024-02-23', status: 'CONFIRMED',   totalAmount: 960 },
]
