import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Plus, Trash2, X, Image as ImageIcon, Layout, Save, RefreshCw } from 'lucide-react';
import { adminSupabase } from '../supabase';
import { toast } from 'react-hot-toast';
import ImageUpload from '../components/ImageUpload';

const Banners = () => {
    const [banners, setBanners] = useState([]);
    const [loading, setLoading] = useState(true);
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [editingBanner, setEditingBanner] = useState(null);
    const [newBanner, setNewBanner] = useState({
        title: '', subtitle: '', image_url: '', bg_color: '#F1F8F1', text_color: '#000000', priority: 0, is_active: true,
        item_id: null, vendor_id: null, action_text: 'ORDER NOW'
    });
    const [products, setProducts] = useState([]);

    useEffect(() => {
        fetchBanners();
        fetchProducts();
    }, []);

    const fetchProducts = async () => {
        const { data } = await adminSupabase.from('products').select('id, name, vendor_id');
        setProducts(data || []);
    };

    const fetchBanners = async () => {
        setLoading(true);
        const { data, error } = await adminSupabase.from('banners').select('*').order('priority', { ascending: false });
        if (error) toast.error("Fetch failed: " + error.message);
        else setBanners(data || []);
        setLoading(false);
    };

    const handleSave = async (e) => {
        e.preventDefault();
        const toastId = toast.loading(editingBanner ? 'Updating...' : 'Creating...');
        
        try {
            if (editingBanner) {
                const { error } = await adminSupabase.from('banners').update(newBanner).eq('id', editingBanner);
                if (error) throw error;
                toast.success('Banner updated!', { id: toastId });
            } else {
                const { error } = await adminSupabase.from('banners').insert([newBanner]);
                if (error) throw error;
                toast.success('Banner created!', { id: toastId });
            }
            setIsModalOpen(false);
            setEditingBanner(null);
            setNewBanner({ title: '', subtitle: '', image_url: '', bg_color: '#F1F8F1', text_color: '#000000', priority: 0, is_active: true, item_id: null, vendor_id: null, action_text: 'ORDER NOW' });
            fetchBanners();
        } catch (err) {
            toast.error(err.message, { id: toastId });
        }
    };

    const handleDelete = async (id) => {
        if (!confirm('Delete this banner?')) return;
        const { error } = await adminSupabase.from('banners').delete().eq('id', id);
        if (error) toast.error(error.message);
        else {
            toast.success('Deleted');
            fetchBanners();
        }
    };

    return (
        <div style={{ padding: '32px' }}>
            <header style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '32px' }}>
                <div>
                    <h1 style={{ fontSize: '2rem', fontWeight: '900', color: '#0F172A' }}>Carousel Banners</h1>
                    <p style={{ color: '#64748B' }}>Manage the hero sliders in the customer application.</p>
                </div>
                <button onClick={() => setIsModalOpen(true)} className="btn-primary" style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                    <Plus size={20} /> Add Slide
                </button>
            </header>

            {loading ? (
                <div style={{ textAlign: 'center', padding: '100px' }}><RefreshCw className="spin" /></div>
            ) : (
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))', gap: '24px' }}>
                    {banners.map(banner => (
                        <div key={banner.id} className="glass-panel" style={{ padding: '0', background: banner.bg_color || '#FFFBEB', color: banner.text_color || '#000000', borderRadius: '16px', overflow: 'hidden', display: 'flex', flexDirection: 'column' }}>
                            <div style={{ display: 'flex', width: '100%', minHeight: '180px' }}>
                                {/* Left Side: Text and Button */}
                                <div style={{ flex: 1, padding: '24px', display: 'flex', flexDirection: 'column', justifyContent: 'center' }}>
                                    <h3 style={{ margin: '0 0 8px 0', fontWeight: '900', fontSize: '1.4rem', lineHeight: '1.2' }}>{banner.title || 'Banner Title'}</h3>
                                    <p style={{ margin: '0 0 16px 0', fontSize: '0.9rem', opacity: 0.8, lineHeight: '1.4' }}>{banner.subtitle || 'Add a subtitle here.'}</p>
                                    <button style={{ padding: '10px 20px', background: banner.text_color || '#0F172A', color: banner.bg_color || '#FFFBEB', border: 'none', borderRadius: '24px', fontWeight: '800', fontSize: '0.8rem', cursor: 'default', width: 'fit-content' }}>
                                        {banner.action_text || 'ORDER NOW'}
                                    </button>
                                </div>
                                {/* Right Side: Image */}
                                <div style={{ flex: 1, background: 'rgba(0,0,0,0.02)', display: 'flex', alignItems: 'center', justifyContent: 'center', position: 'relative' }}>
                                    {banner.image_url ? (
                                        <img src={banner.image_url} style={{ width: '100%', height: '100%', objectFit: 'cover', position: 'absolute', inset: 0 }} alt="banner" />
                                    ) : (
                                        <ImageIcon size={48} color="#CBD5E1" />
                                    )}
                                </div>
                            </div>
                            {/* Card Footer: Admin Controls */}
                            <div style={{ padding: '12px 16px', background: 'white', borderTop: '1px solid #E2E8F0', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                                <span style={{ fontSize: '0.7rem', fontWeight: '800', background: '#F1F5F9', color: '#64748B', padding: '4px 8px', borderRadius: '4px' }}>
                                    PRIORITY: {banner.priority}
                                </span>
                                <div style={{ display: 'flex', gap: '8px' }}>
                                    <button onClick={() => { setEditingBanner(banner.id); setNewBanner(banner); setIsModalOpen(true); }} style={{ padding: '8px', borderRadius: '8px', border: 'none', background: '#F8FAFC', cursor: 'pointer', color: '#0F172A' }}><Layout size={16} /></button>
                                    <button onClick={() => handleDelete(banner.id)} style={{ padding: '8px', borderRadius: '8px', border: 'none', background: '#FEE2E2', color: '#EF4444', cursor: 'pointer' }}><Trash2 size={16} /></button>
                                </div>
                            </div>
                        </div>
                    ))}
                </div>
            )}

            <AnimatePresence>
                {isModalOpen && (
                    <div style={{ position: 'fixed', inset: 0, zIndex: 9999, display: 'grid', placeItems: 'center', padding: '20px' }}>
                        <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} onClick={() => setIsModalOpen(false)} style={{ position: 'absolute', inset: 0, background: 'rgba(15, 23, 42, 0.4)', backdropFilter: 'blur(10px)' }} />
                        <motion.div initial={{ opacity: 0, y: 30 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: 30 }} style={{ position: 'relative', background: 'white', width: '100%', maxWidth: '500px', borderRadius: '32px', padding: '40px' }}>
                            <h2 style={{ marginBottom: '24px', fontWeight: '900' }}>{editingBanner ? 'Edit Slide' : 'New Slide'}</h2>
                            <form onSubmit={handleSave} style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
                                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                                    <input required placeholder="Main Title (e.g. SPECIAL OFFER)" value={newBanner.title} onChange={e => setNewBanner({...newBanner, title: e.target.value})} style={{ padding: '12px', borderRadius: '12px', border: '1px solid #E2E8F0' }} />
                                    <input placeholder="Button Text (e.g. ORDER NOW)" value={newBanner.action_text || ''} onChange={e => setNewBanner({...newBanner, action_text: e.target.value})} style={{ padding: '12px', borderRadius: '12px', border: '1px solid #E2E8F0' }} />
                                </div>
                                <input placeholder="Subtitle" value={newBanner.subtitle} onChange={e => setNewBanner({...newBanner, subtitle: e.target.value})} style={{ padding: '12px', borderRadius: '12px', border: '1px solid #E2E8F0' }} />
                                <ImageUpload label="Banner PNG (Transparent preferred)" value={newBanner.image_url} onUpload={url => setNewBanner({...newBanner, image_url: url})} folder="banners" />
                                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                                    <div>
                                        <label style={{ fontSize: '0.7rem', fontWeight: '800', color: '#64748B', display: 'block', marginBottom: '4px' }}>BG COLOR</label>
                                        <input type="color" value={newBanner.bg_color} onChange={e => setNewBanner({...newBanner, bg_color: e.target.value})} style={{ width: '100%', height: '40px', border: 'none', borderRadius: '8px' }} />
                                    </div>
                                    <div>
                                        <label style={{ fontSize: '0.7rem', fontWeight: '800', color: '#64748B', display: 'block', marginBottom: '4px' }}>PRIORITY</label>
                                        <input type="number" value={newBanner.priority} onChange={e => setNewBanner({...newBanner, priority: parseInt(e.target.value)})} style={{ width: '100%', padding: '8px', borderRadius: '8px', border: '1px solid #E2E8F0' }} />
                                    </div>
                                </div>

                                <div>
                                    <label style={{ fontSize: '0.7rem', fontWeight: '800', color: '#64748B', display: 'block', marginBottom: '4px' }}>LINK TO ITEM (Optional)</label>
                                    <select 
                                        value={newBanner.item_id || ''} 
                                        onChange={e => {
                                            const prod = products.find(p => p.id === e.target.value);
                                            setNewBanner({
                                                ...newBanner, 
                                                item_id: e.target.value || null,
                                                vendor_id: prod ? prod.vendor_id : null
                                            });
                                        }}
                                        style={{ width: '100%', padding: '12px', borderRadius: '12px', border: '1px solid #E2E8F0' }}
                                    >
                                        <option value="">No link</option>
                                        {products.map(p => (
                                            <option key={p.id} value={p.id}>{p.name}</option>
                                        ))}
                                    </select>
                                </div>
                                <button type="submit" className="btn-primary" style={{ marginTop: '12px', padding: '16px', borderRadius: '16px' }}>
                                    <Save size={18} style={{ marginRight: '8px' }} /> SAVE CONFIGURATION
                                </button>
                            </form>
                        </motion.div>
                    </div>
                )}
            </AnimatePresence>
        </div>
    );
};

export default Banners;
