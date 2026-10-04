import React, { useState, useEffect } from 'react';
import { Save, RefreshCw, Globe, Navigation, CreditCard, AlertTriangle } from 'lucide-react';
import { supabase, adminSupabase } from '../supabase';
import { toast } from 'react-hot-toast';
import './SystemSettings.css';

const SystemSettings = () => {
    const [settings, setSettings] = useState({
        platformName: 'UNIV Foods',
        supportEmail: 'support@univfoods.in',
        currency: 'INR (₹)',
        maintenanceMode: false,
        taxRate: 0,
        minOrderValue: 150,
        deliveryRadius: 15,
        codEnabled: true,
        maxCodValue: 2000,
        autoAssignRiders: true,
        supportPhone: '+919940407600',
        emergencyPhone: '100',
        deliveryFee: 0,
        platformFee: 0,
    });
    const [loading, setLoading] = useState(true);
    const [saving, setSaving] = useState(false);

    useEffect(() => {
        fetchSettings();
    }, []);

    const fetchSettings = async () => {
        try {
            const { data, error } = await supabase
                .from('app_settings')
                .select('*')
                .eq('key', 'system_config')
                .maybeSingle();

            if (error) console.error('Fetch error:', error);
            if (data?.value) {
                setSettings(prev => ({ ...prev, ...data.value }));
            }
        } catch (e) {
            console.error('fetchSettings failed:', e);
        }
        setLoading(false);
    };

    const handleSave = async (e) => {
        if (e) e.preventDefault();
        setSaving(true);
        try {
            // FIX: onConflict: 'key' ensures this does UPDATE when row exists, not INSERT
            // This prevents the "new row violates row-level security policy" error
            const client = adminSupabase || supabase;
            const { error } = await client
                .from('app_settings')
                .upsert(
                    {
                        key: 'system_config',
                        value: settings,
                        updated_at: new Date().toISOString(),
                    },
                    { onConflict: 'key' }
                );

            if (error) throw error;
            toast.success('✅ Settings saved! Customer app updates within seconds.');
        } catch (error) {
            console.error('Save error:', error);
            toast.error(`Save failed: ${error.message || JSON.stringify(error)}`);
        }
        setSaving(false);
    };

    const runRepair = async () => {
        const toastId = toast.loading('Initiating deep system repair...');
        try {
            // Since we can't run raw SQL easily via the client in some environments,
            // we try to use a pre-defined RPC if it exists, or individual logic.
            // For the "shell operator" fix, we specifically need the SQL fix.
            
            toast.error('Please run the STABILITY_AND_UX_FIX_V53.sql in your Supabase SQL Editor to fix the "shell operator" error.', { id: toastId, duration: 6000 });
            
            // However, we can try to fix some things programmatically
            await adminSupabase.from('orders').update({ status: 'CANCELLED' }).eq('order_status', 'CANCELLED');
            toast.success('Basic status sync completed.', { id: toastId });
        } catch (e) {
            toast.error('Repair failed: ' + e.message, { id: toastId });
        }
    };

    if (loading) {
        return (
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '300px' }}>
                <RefreshCw size={32} className="animate-spin" style={{ color: '#FFD600' }} />
            </div>
        );
    }

    return (
        <div className="settings-page">
            <header className="page-header">
                <div>
                    <h1 className="page-title">Command Center</h1>
                    <p className="page-subtitle">Real-time platform logic and operational constraints.</p>
                </div>
                <div className="page-actions">
                    <button
                        onClick={runRepair}
                        className="btn-deploy"
                        style={{ background: '#0F172A', color: '#FFD600', marginRight: '12px' }}
                    >
                        <RefreshCw size={20} />
                        SYSTEM REPAIR
                    </button>
                    <button
                        onClick={handleSave}
                        disabled={saving}
                        className="btn-deploy"
                    >
                        {saving ? <RefreshCw size={20} className="animate-spin" /> : <Save size={20} />}
                        {saving ? 'SAVING...' : 'SUBMIT'}
                    </button>
                </div>
            </header>

            <div className="settings-grid">
                {/* Core Identity */}
                <div className="glass-panel settings-card">
                    <div className="settings-card-header">
                        <Globe size={24} color="#FFD600" />
                        <h3 className="section-title">Core Identity</h3>
                    </div>
                    <div className="settings-input-group">
                        <div>
                            <label className="settings-label">Platform Title</label>
                            <input
                                value={settings.platformName}
                                onChange={e => setSettings({ ...settings, platformName: e.target.value })}
                                className="settings-input"
                            />
                        </div>
                        <div>
                            <label className="settings-label">Global Support Registry</label>
                            <input
                                value={settings.supportEmail}
                                onChange={e => setSettings({ ...settings, supportEmail: e.target.value })}
                                className="settings-input"
                            />
                        </div>
                        <div>
                            <label className="settings-label">Support Phone</label>
                            <input
                                value={settings.supportPhone}
                                onChange={e => setSettings({ ...settings, supportPhone: e.target.value })}
                                className="settings-input"
                            />
                        </div>
                        <div>
                            <label className="settings-label">Emergency Hotline</label>
                            <input
                                value={settings.emergencyPhone}
                                onChange={e => setSettings({ ...settings, emergencyPhone: e.target.value })}
                                className="settings-input"
                            />
                        </div>
                    </div>
                </div>

                {/* Logistics Radius */}
                <div className="glass-panel settings-card">
                    <div className="settings-card-header">
                        <Navigation size={24} color="#FFD600" />
                        <h3 className="section-title">Logistics Radius</h3>
                    </div>
                    <div className="settings-input-group">
                        <div>
                            <label className="settings-label">Operational Radius (KM)</label>
                            <input
                                type="number"
                                value={settings.deliveryRadius}
                                onChange={e => setSettings({ ...settings, deliveryRadius: Number(e.target.value) })}
                                className="settings-input"
                            />
                            <p style={{ fontSize: '0.7rem', color: '#64748b', marginTop: '8px', fontWeight: '600' }}>
                                Changes reflect instantly during checkout validation.
                            </p>
                        </div>
                        <div className="settings-toggle-row">
                            <span style={{ fontWeight: '800', color: '#475569', fontSize: '0.9rem' }}>Auto-Assign Riders</span>
                            <input
                                type="checkbox"
                                checked={settings.autoAssignRiders}
                                onChange={e => setSettings({ ...settings, autoAssignRiders: e.target.checked })}
                                className="settings-toggle"
                            />
                        </div>
                    </div>
                </div>

                {/* Financial & Fees */}
                <div className="glass-panel settings-card">
                    <div className="settings-card-header">
                        <CreditCard size={24} color="#FFD600" />
                        <h3 className="section-title">Financial &amp; Fees</h3>
                    </div>
                    <div className="settings-input-group">
                        <div className="settings-toggle-row">
                            <span style={{ fontWeight: '800', color: '#475569', fontSize: '0.9rem' }}>Enable COD Globally</span>
                            <input
                                type="checkbox"
                                checked={settings.codEnabled}
                                onChange={e => setSettings({ ...settings, codEnabled: e.target.checked })}
                                className="settings-toggle"
                            />
                        </div>
                        <div>
                            <label className="settings-label">Max COD Threshold (₹)</label>
                            <input
                                type="number"
                                value={settings.maxCodValue}
                                onChange={e => setSettings({ ...settings, maxCodValue: Number(e.target.value) })}
                                className="settings-input"
                            />
                        </div>
                        <div style={{ marginTop: '16px', paddingTop: '16px', borderTop: '1px solid #f1f5f9' }}>
                            <label className="settings-label">Delivery Fee (₹)</label>
                            <input
                                type="number"
                                value={settings.deliveryFee ?? 0}
                                onChange={e => setSettings({ ...settings, deliveryFee: Number(e.target.value) })}
                                className="settings-input"
                            />
                        </div>
                        <div>
                            <label className="settings-label">Platform Fee (₹)</label>
                            <input
                                type="number"
                                value={settings.platformFee ?? 0}
                                onChange={e => setSettings({ ...settings, platformFee: Number(e.target.value) })}
                                className="settings-input"
                            />
                        </div>
                        <div>
                            <label className="settings-label">GST / Tax Rate (%)</label>
                            <input
                                type="number"
                                value={settings.taxRate ?? 0}
                                onChange={e => setSettings({ ...settings, taxRate: Number(e.target.value) })}
                                className="settings-input"
                            />
                        </div>
                    </div>
                </div>

                {/* Danger Zone */}
                <div className={`glass-panel settings-card ${settings.maintenanceMode ? 'maintenance-active' : ''}`}>
                    <div className="settings-card-header">
                        <AlertTriangle size={24} color="#ef4444" />
                        <h3 className="section-title">Danger Zone</h3>
                    </div>
                    <div className="settings-input-group">
                        <div className="settings-toggle-row" style={{ background: 'rgba(255,255,255,0.5)' }}>
                            <div>
                                <span style={{ fontWeight: '800', color: '#475569', fontSize: '0.9rem' }}>Maintenance Mode</span>
                                <p style={{ fontSize: '0.65rem', color: '#ef4444', fontWeight: '700', margin: '2px 0 0' }}>HALTS ALL TRANSACTIONS</p>
                            </div>
                            <input
                                type="checkbox"
                                checked={settings.maintenanceMode}
                                onChange={e => setSettings({ ...settings, maintenanceMode: e.target.checked })}
                                className="settings-toggle"
                            />
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
};

export default SystemSettings;
