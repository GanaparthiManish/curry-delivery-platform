import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Plus, Search, MapPin, Store, Star, X, RefreshCw, Tag, Trash2 } from 'lucide-react';
import { supabase, adminSupabase } from '../supabase';
import { COLLECTIONS } from '../constants';
import { toast } from 'react-hot-toast';
import { useNavigate, useLocation } from 'react-router-dom';
import ImageUpload from '../components/ImageUpload';
import { MapContainer, TileLayer, Marker, useMapEvents, Popup } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import L from 'leaflet';
import './Vendors.css';

// Fix Leaflet Marker
delete L.Icon.Default.prototype._getIconUrl;
L.Icon.Default.mergeOptions({
    iconRetinaUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon-2x.png',
    iconUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon.png',
    shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-shadow.png',
});

const MapPicker = ({ position, setPosition }) => {
    const map = useMapEvents({
        click(e) {
            setPosition(e.latlng);
        },
    });

    useEffect(() => {
        if (position) {
            map.flyTo(position, map.getZoom());
        }
    }, [position, map]);

    return position ? (
        <Marker position={position}>
            <Popup>Vendor Location</Popup>
        </Marker>
    ) : null;
};

const Toggle = ({ active, onToggle, label, disabled }) => {
    return (
        <div 
            style={{ 
                display: 'flex', 
                alignItems: 'center', 
                gap: '10px', 
                cursor: disabled ? 'not-allowed' : 'pointer',
                opacity: disabled ? 0.6 : 1,
                pointerEvents: disabled ? 'none' : 'auto'
            }} 
            onClick={(e) => { 
                e.preventDefault();
                e.stopPropagation(); 
                if (!disabled) onToggle(); 
            }}
        >
            <div style={{
                width: '40px',
                height: '20px',
                backgroundColor: active ? '#10B981' : '#CBD5E1',
                borderRadius: '20px',
                position: 'relative',
                transition: 'all 0.3s ease'
            }}>
                <div style={{
                    width: '14px',
                    height: '14px',
                    backgroundColor: 'white',
                    borderRadius: '50%',
                    position: 'absolute',
                    top: '3px',
                    left: active ? '23px' : '3px',
                    transition: 'all 0.3s cubic-bezier(0.4, 0, 0.2, 1)',
                    boxShadow: '0 1px 3px rgba(0,0,0,0.2)'
                }} />
            </div>
            {label && <span style={{ fontSize: '0.75rem', fontWeight: '800', color: active ? '#10B981' : '#64748B', textTransform: 'uppercase' }}>{label}</span>}
        </div>
    );
};

const Vendors = () => {
    const navigate = useNavigate();
    const location = useLocation();
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [vendors, setVendors] = useState([]);
    const [loading, setLoading] = useState(true);
    const [searchTerm, setSearchTerm] = useState('');
    const [editingVendor, setEditingVendor] = useState(null);
    const [selectedVendorNode, setSelectedVendorNode] = useState(null);
    const [vendorItems, setVendorItems] = useState([]);
    const [categories, setCategories] = useState([]);
    const [loadMenu, setLoadMenu] = useState(false);
    const [productModalOpen, setProductModalOpen] = useState(false);
    const [editingProduct, setEditingProduct] = useState(null);
    const [productForm, setProductForm] = useState({
        name: '', description: '', price: '', category_id: '', is_veg: true, is_available: true, image_url: '', item_type: 'NORMAL_VENDOR_ITEM'
    });

    useEffect(() => {
        if (editingProduct) {
            setProductForm({
                name: editingProduct.name,
                description: editingProduct.description || '',
                price: editingProduct.price,
                category_id: editingProduct.category_id || '',
                is_veg: editingProduct.is_veg,
                is_available: editingProduct.is_available,
                image_url: editingProduct.image_url || '',
                item_type: editingProduct.item_type || 'NORMAL_VENDOR_ITEM'
            });
        } else {
            setProductForm({
                name: '', description: '', price: '', category_id: '', is_veg: true, is_available: true, image_url: '', item_type: 'NORMAL_VENDOR_ITEM'
            });
        }
    }, [editingProduct, productModalOpen]);

    // Default center (Srivilliputhur)
    const DEFAULT_CENTER = { lat: 9.5100, lng: 77.6300 };

    const [newVendor, setNewVendor] = useState({
        name: '', address: '', phone: '', manager: '',
        cuisine: 'North Indian', openTime: '09:00', closeTime: '22:00',
        banner_url: '',
        is_pure_veg: false,
        has_offers: false,
        latitude: '',
        longitude: '',
        delivery_radius_km: 15,
        email: ''
    });

    useEffect(() => {
        if (location.state?.registrationData) {
            const reg = location.state.registrationData;
            setNewVendor({
                name: reg.name,
                address: reg.address || reg.message || '',
                phone: reg.phone,
                manager: reg.name,
                cuisine: 'North Indian',
                openTime: '09:00',
                closeTime: '22:00',
                banner_url: '',
                latitude: reg.lat || DEFAULT_CENTER.lat,
                longitude: reg.lng || DEFAULT_CENTER.lng,
                delivery_radius_km: 15,
                is_pure_veg: false,
                has_offers: false,
                email: reg.email || ''
            });
            setIsModalOpen(true);
            setEditingVendor(null);
            fetchVendors();
        }
    }, [location]);

    useEffect(() => {
        console.log("🛰️ VENDORS_MODULE_LOADED_V2.1");
        fetchVendors();
        fetchCategories();
        const sub = supabase.channel('vendors-live')
            .on('postgres_changes', { event: '*', schema: 'public', table: COLLECTIONS.VENDORS }, fetchVendors)
            .subscribe();
        return () => supabase.removeChannel(sub);
    }, []);

    const fetchCategories = async () => {
        const { data } = await adminSupabase.from('categories').select('id, name').eq('is_active', true).order('priority', { ascending: false });
        if (data) setCategories(data);
    };

    const fetchVendorMenu = async (vendorId, showLoading = true) => {
        if (!vendorId) {
            console.error("🔴 MENU_FETCH_ABORTED: No vendor ID provided");
            return;
        }
        if (showLoading) setLoadMenu(true);
        console.log(`🛰️ Fetching menu for vendor: ${vendorId}`);
        try {
            const { data, error } = await adminSupabase
                .from('products')
                .select('*')
                .eq('vendor_id', vendorId)
                .order('name');
            
            if (error) {
                console.error("🔴 MENU_FETCH_ERROR:", error);
                toast.error("Menu Sync Failed: " + error.message);
            } else if (data) {
                setVendorItems(data);
                console.log(`🛰️ Menu sync complete. Loaded ${data.length} items.`);
            }
        } catch (err) {
            console.error("Critical Menu Fetch Failure:", err);
        } finally {
            if (showLoading) setLoadMenu(false);
        }
    };

    const fetchVendors = async (showLoading = true) => {
        if (showLoading) setLoading(true);
        try {
            const { data, error } = await adminSupabase.from(COLLECTIONS.VENDORS).select('*').order('created_at', { ascending: false });
            if (error) {
                console.error("🔴 VENDOR_FETCH_ERROR:", error);
                toast.error("Failed to load vendors: " + error.message);
            } else if (data) {
                setVendors(data);
                console.log(`🛰️ Loaded ${data.length} vendors into local grid.`);
            }
        } catch (err) {
            console.error('Critical Fetch Failure:', err);
            toast.error("Critical Signal Loss: Check Supabase Connection");
        } finally {
            if (showLoading) setLoading(false);
        }
    };

    const handleDelete = async (id) => {
        if (!confirm("⚠️ WARNING: This will PERMANENTLY delete this vendor and ALL their products/menu items. This cannot be undone. \n\nProceed with full decommission?")) return;
        
        const toastId = toast.loading("Decommissioning vendor and clearing menu data...");
        console.log('🗑️ Starting cascading delete for vendor:', id);
        
        try {
            const { error } = await adminSupabase
                .from(COLLECTIONS.VENDORS)
                .delete()
                .eq('id', id);
            
            if (error) {
                console.error("🔴 VENDOR_DELETE_ERROR:", error);
                // Check if it's a foreign key error
                const errorMsg = error.code === '23503' 
                    ? "Cannot delete: Vendor has active orders or items. (Run the STEP_1 SQL patch to fix this)"
                    : error.message;
                toast.error("DECOMMISSION FAILED: " + errorMsg, { id: toastId });
            } else {
                toast.success("Vendor and all related products deleted.", { id: toastId });
                fetchVendors();
                if (selectedVendorNode?.id === id) {
                    setSelectedVendorNode(null);
                    setVendorItems([]);
                }
            }
        } catch (err) {
            console.error("🔴 DELETE_CRASH:", err);
            toast.error("System connection error during delete", { id: toastId });
        }
    };

    const handleCreateVendor = async (e) => {
        e.preventDefault();
        try {
            const payload = {
                name: newVendor.name,
                shop_name: newVendor.name,
                cuisine_type: newVendor.cuisine,
                address: newVendor.address,
                phone: newVendor.phone,
                email: newVendor.email,
                manager: newVendor.manager,
                open_time: newVendor.openTime,
                close_time: newVendor.closeTime,
                latitude: parseFloat(newVendor.latitude) || 9.51,
                longitude: parseFloat(newVendor.longitude) || 77.63,
                delivery_radius_km: parseFloat(newVendor.delivery_radius_km) || 15,
                is_pure_veg: !!newVendor.is_pure_veg,
                has_offers: !!newVendor.has_offers,
                banner_url: newVendor.banner_url || '',
                image_url: newVendor.banner_url || '',
                status: editingVendor ? undefined : 'ONLINE',
                rating: editingVendor ? (vendors.find(v => v.id === editingVendor)?.rating || 5.0) : 5.0,
                is_approved: true,
                approval_status: 'APPROVED',
                is_active: true,
                is_verified: true,
                commission_rate: 10,
                min_order_value: 0,
                cost_for_two: 250,
                avg_prep_time: 25,
                is_open: true
            };

            if (editingVendor) {
                const { error } = await adminSupabase.from(COLLECTIONS.VENDORS).update(payload).eq('id', editingVendor);
                if (error) {
                    console.error("Update Error:", error);
                    throw error;
                }
                toast.success("Vendor updated successfully!");
            } else {
                const { error } = await adminSupabase.from(COLLECTIONS.VENDORS).insert([payload]);
                if (error) {
                    console.error("Insert Error:", error);
                    throw error;
                }
                toast.success("New point deployed successfully!");
            }
            setIsModalOpen(false);
            setEditingVendor(null);
            setNewVendor({ name: '', address: '', phone: '', manager: '', cuisine: 'North Indian', openTime: '09:00', closeTime: '22:00', banner_url: '', delivery_radius_km: 15, email: '' });
            fetchVendors();
        } catch (err) {
            console.error("FATAL_DEPLOY_FAULT:", err);
            toast.error("DEPLOYMENT ERROR: " + err.message);
        }
    };

    const handleEditVendor = (vendor) => {
        setEditingVendor(vendor.id);
        const lat = vendor.latitude || DEFAULT_CENTER.lat;
        const lng = vendor.longitude || DEFAULT_CENTER.lng;

        setNewVendor({
            name: vendor.name,
            address: vendor.address || '',
            phone: vendor.phone || '',
            manager: vendor.manager || '',
            cuisine: vendor.cuisine_type || 'North Indian',
            openTime: vendor.open_time || '09:00',
            closeTime: vendor.close_time || '22:00',
            banner_url: vendor.banner_url || '',
            is_pure_veg: vendor.is_pure_veg || false,
            has_offers: vendor.has_offers || false,
            latitude: lat,
            longitude: lng,
            delivery_radius_km: vendor.delivery_radius_km || 10,
            email: vendor.email || ''
        });
        setIsModalOpen(true);
    };

    const simulateVendor = async () => {
        const testVendor = {
            name: "Cloud Kitchen " + Math.floor(Math.random() * 1000),
            shop_name: "Cloud Kitchen " + Math.floor(Math.random() * 1000), // Critical missing field
            address: "Srivilliputhur Digital Zone",
            phone: "+91 99887766" + Math.floor(Math.random() * 9),
            manager: "Admin Simulation",
            cuisine_type: "Virtual Curry",
            status: "ONLINE",
            latitude: DEFAULT_CENTER.lat + (Math.random() - 0.5) * 0.01,
            longitude: DEFAULT_CENTER.lng + (Math.random() - 0.5) * 0.01,
            rating: 5.0,
            is_approved: true,
            approval_status: 'APPROVED'
        };
        const { error } = await adminSupabase.from(COLLECTIONS.VENDORS).insert([testVendor]);
        if (error) {
            console.error("Simulation Error:", error);
            toast.error("Deployment Interrupted: " + (error.message || "Schema Mismatch"));
        }
        else {
            toast.success("Partner Node Deployed in Real-time!");
            fetchVendors();
        }
    };

    const toggleStatus = async (v) => {
        const isOnline = v.status === 'ONLINE';
        const newStatus = isOnline ? 'OFFLINE' : 'ONLINE';
        const newIsOpen = !isOnline;

        const { error } = await adminSupabase.from(COLLECTIONS.VENDORS)
            .update({
                status: newStatus,
                is_open: newIsOpen
            })
            .eq('id', v.id);

        if (error) toast.error("Relay Fault: " + error.message);
        else {
            toast.success(`Node ${v.name} now ${newStatus}`);
            fetchVendors(false); // 🔄 INSTANT REFRESH WITHOUT FLICKER
        }
    };

    const handleSelectVendor = (v) => {
        setSelectedVendorNode(v);
        fetchVendorMenu(v.id);
        // Scroll to menu section
        setTimeout(() => {
            const menuEl = document.getElementById('vendor-menu-section');
            if (menuEl) menuEl.scrollIntoView({ behavior: 'smooth' });
        }, 300);
    };

    const [processingId, setProcessingId] = useState(null);

    const handleProductSave = async (productData) => {
        if (processingId) return;
        const opType = productData.id ? 'UPDATE' : 'INSERT';
        console.log(`🚀 STARTING_${opType}:`, productData);
        
        const toastId = toast.loading(productData.id ? "Updating menu item..." : "Adding to menu...");
        if (!productData.item_type) {
            toast.error('Please select an Item Type (Popular vs Normal)', { id: toastId });
            return;
        }
        setProcessingId('save-' + (productData.id || 'new'));
        
        try {
            const payload = {
                name: productData.name,
                description: productData.description || '',
                price: parseFloat(productData.price) || 0,
                category: productData.category || 'Main',
                category_id: productData.category_id || null,
                is_available: productData.is_available ?? true,
                is_veg: productData.is_veg ?? true,
                image_url: productData.image_url || '',
                item_type: productData.item_type || 'NORMAL_VENDOR_ITEM'
            };

            if (productData.id) {
                // OPTIMISTIC UPDATE
                const originalItems = [...vendorItems];
                setVendorItems(prev => prev.map(item => 
                    (item.id && String(item.id) === String(productData.id)) ? { ...item, ...payload } : item
                ));

                const { error: updateErr } = await adminSupabase
                    .from('products')
                    .update(payload)
                    .eq('id', productData.id);
                
                if (updateErr) {
                    setVendorItems(originalItems); // Rollback
                    throw updateErr;
                }
                toast.success("Item Updated Successfully", { id: toastId });
            } else {
                // INSERT
                const fullPayload = { ...payload, vendor_id: selectedVendorNode.id };
                const { data, error: insertErr } = await adminSupabase
                    .from('products')
                    .insert([fullPayload])
                    .select();
                
                if (insertErr) throw insertErr;
                
                if (data && data[0]) {
                    setVendorItems(prev => [data[0], ...prev]);
                }
                toast.success("Item Added to Menu", { id: toastId });
            }

            setProductModalOpen(false);
            setEditingProduct(null);
            
            // Critical: Refresh with a slight delay to ensure DB sync
            setTimeout(() => {
                if (selectedVendorNode?.id) fetchVendorMenu(selectedVendorNode.id, false);
            }, 500);

        } catch (error) {
            console.error(`❌ ${opType}_FAILED:`, error);
            toast.error(`${opType} FAILED: ${error.message}`, { id: toastId });
            // Re-fetch to normalize state
            if (selectedVendorNode?.id) fetchVendorMenu(selectedVendorNode.id);
        } finally {
            setProcessingId(null);
        }
    };

    const handleProductDelete = async (id) => {
        console.log("🗑️ ATTEMPTING_DELETE:", id);
        if (!id || id === 'null') {
            toast.error("Unresolvable Item - Refreshing list");
            if (selectedVendorNode?.id) fetchVendorMenu(selectedVendorNode.id);
            return;
        }
        if (processingId === id) return;
        if (!window.confirm('Delete this item from the station menu?')) return;

        const toastId = toast.loading("Purging item...");
        setProcessingId(id);
        
        // Optimistic Remove
        const previousItems = [...vendorItems];
        setVendorItems(prev => prev.filter(item => String(item.id) !== String(id)));

        try {
            console.log("🗑️ DELETING_ITEM:", id);
            const { error } = await adminSupabase.from('products').delete().eq('id', id);
            
            if (error) {
                setVendorItems(previousItems); // Rollback
                throw error;
            }
            
            toast.success("Product Purged", { id: toastId });
        } catch (error) {
            console.error("❌ DELETE_FAILED:", error);
            toast.error("PURGE FAILED: " + error.message, { id: toastId });
        } finally {
            setProcessingId(null);
        }
    };

    const toggleProductAvailability = async (id, currentStatus) => {
        if (!id || id === 'null') {
            toast.error("Sync Error: No valid ID");
            if (selectedVendorNode?.id) fetchVendorMenu(selectedVendorNode.id);
            return;
        }
        if (processingId === `toggle-${id}`) return;
        
        setProcessingId(`toggle-${id}`);
        // Optimistic Toggle
        const originalItems = [...vendorItems];
        setVendorItems(prev => prev.map(item => 
            (item.id && String(item.id) === String(id)) ? { ...item, is_available: !currentStatus } : item
        ));

        try {
            console.log(`🔌 TOGGLING_AVAILABILITY [${id}]: ${currentStatus} -> ${!currentStatus}`);
            const { error } = await adminSupabase
                .from('products')
                .update({ is_available: !currentStatus })
                .eq('id', id);
            
            if (error) throw error;
            toast.success("Availability Synced");
        } catch (error) {
            console.error("❌ TOGGLE_FAILED:", error);
            toast.error("SYNC FAILED: " + error.message);
            // Rollback
            setVendorItems(prev => prev.map(item => 
                String(item.id) === String(id) ? { ...item, is_available: currentStatus } : item
            ));
        } finally {
            setProcessingId(null);
        }
    };

    const geocodeAddress = async () => {
        if (!newVendor.address) return toast.error("Enter address first");
        const loadingToast = toast.loading("Geocoding...");
        try {
            const res = await fetch(`https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(newVendor.address)}`);
            const data = await res.json();
            if (data && data.length > 0) {
                const { lat, lon } = data[0];
                setNewVendor(prev => ({ ...prev, latitude: parseFloat(lat), longitude: parseFloat(lon) }));
                toast.success("Address found on map!");
            } else {
                toast.error("Could not locate address");
            }
        } catch (e) {
            toast.error("Geocoding failed");
        } finally {
            toast.dismiss(loadingToast);
        }
    };

    const filteredVendors = vendors.filter(v => v.name?.toLowerCase().includes(searchTerm.toLowerCase()));

    return (
        <div className="vendors-container" style={{ padding: '32px', background: 'transparent', minHeight: '100vh', paddingBottom: '100px' }}>
            {/* Header Section */}
            <header className="vendors-header">
                <div style={{ background: '#ef4444', color: 'white', padding: '12px 24px', borderRadius: '12px', marginBottom: '20px', fontWeight: '900' }}>
                    ⚠️ LOGISTICS GRID: AUTH SYNC ACTIVE
                </div>
                <div>
                    <h1 className="page-title">Vendor Partners</h1>
                    <p style={{ color: '#64748b', fontSize: '1rem', marginTop: '4px' }}>
                        Manage platform partner restaurants and service nodes.
                    </p>
                </div>
                <div style={{ display: 'flex', gap: '12px' }}>
                    <button onClick={simulateVendor} className="btn-primary" style={{ background: '#0F172A', color: 'white' }}>
                        <RefreshCw size={18} color="#FFD600" style={{ marginRight: '8px' }} /> SIMULATE PARTNER
                    </button>
                    <button
                        onClick={() => {
                            setNewVendor({
                                name: '', address: '', phone: '', manager: '',
                                cuisine: 'North Indian', openTime: '09:00', closeTime: '22:00',
                                banner_url: '',
                                latitude: DEFAULT_CENTER.lat,
                                longitude: DEFAULT_CENTER.lng,
                                delivery_radius_km: 15,
                                is_pure_veg: false, has_offers: false,
                                email: ''
                            });
                            setEditingVendor(null);
                            setIsModalOpen(true);
                        }}
                        className="btn-primary"
                    >
                        <Plus size={18} /> Add New Vendor
                    </button>
                </div>
            </header>

            {/* Stats Row */}
            <div className="vendors-stats-grid" style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: '24px', marginBottom: '32px' }}>
                <div className="glass-panel" style={{ padding: '24px', display: 'flex', alignItems: 'center', gap: '16px', border: 'none', boxShadow: '0 4px 20px rgba(0,0,0,0.03)' }}>
                    <div style={{ background: '#FFD600', width: '48px', height: '48px', borderRadius: '12px', display: 'grid', placeItems: 'center', boxShadow: '0 4px 12px rgba(255, 214, 0, 0.3)' }}>
                        <Store size={22} color="#0F172A" />
                    </div>
                    <div>
                        <p style={{ fontSize: '0.75rem', color: '#64748b', fontWeight: '600', textTransform: 'uppercase' }}>Total Vendors</p>
                        <h2 style={{ fontSize: '1.25rem', fontWeight: '800', color: '#0f172a' }}>{vendors.length} Nodes</h2>
                    </div>
                </div>

                <div className="glass-panel" style={{ padding: '24px', display: 'flex', alignItems: 'center', gap: '16px', border: 'none', boxShadow: '0 4px 20px rgba(0,0,0,0.03)' }}>
                    <div style={{ background: '#FFD600', width: '48px', height: '48px', borderRadius: '12px', display: 'grid', placeItems: 'center', boxShadow: '0 4px 12px rgba(255, 214, 0, 0.3)' }}>
                        <Star size={22} color="#0F172A" />
                    </div>
                    <div>
                        <p style={{ fontSize: '0.75rem', color: '#64748B', fontWeight: '800', textTransform: 'uppercase' }}>Avg Rating</p>
                        <h2 style={{ fontSize: '1.25rem', fontWeight: '900', color: '#0F172A' }}>{vendors.length > 0 ? (vendors.reduce((acc, v) => acc + (v.rating || 0), 0) / vendors.length).toFixed(1) : '5.0'} ⭐</h2>
                    </div>
                </div>

                <div className="glass-panel" style={{ padding: '24px', display: 'flex', alignItems: 'center', gap: '12px' }}>
                    <Search size={18} color="#64748b" />
                    <input
                        type="text"
                        placeholder="Search vendors..."
                        value={searchTerm}
                        onChange={(e) => setSearchTerm(e.target.value)}
                        style={{ background: 'transparent', border: 'none', outline: 'none', fontSize: '0.9rem', fontWeight: '500', width: '100%', color: '#0f172a' }}
                    />
                </div>
            </div>

            {/* Table Section */}
            <div className="glass-panel vendors-table-container" style={{ background: 'white', padding: '40px', border: '1px solid rgba(0,0,0,0.03)' }}>
                {loading ? (
                    <div style={{ textAlign: 'center', padding: '100px 0' }}>
                        <div className="loader" style={{ fontSize: '1.2rem', fontWeight: '800', color: '#64748b' }}>Refreshing Infrastructure...</div>
                    </div>
                ) : (
                    <div style={{ overflowX: 'auto' }}>
                        <table className="responsive-table" style={{ width: '100%', borderCollapse: 'separate', borderSpacing: '0 20px' }}>
                            <thead>
                                <tr style={{ color: '#94a3b8', fontSize: '0.85rem', fontWeight: '800', textAlign: 'left', textTransform: 'uppercase', letterSpacing: '1.5px' }}>
                                    <th style={{ padding: '0 20px' }}>Vendor Info</th>
                                    <th style={{ padding: '0 20px' }}>Manager</th>
                                    <th style={{ padding: '0 20px' }}>Rating</th>
                                    <th style={{ padding: '0 20px' }}>Earnings</th>
                                    <th style={{ padding: '0 20px' }}>Status</th>
                                    <th style={{ padding: '0 20px' }}>Menu & Control</th>

                                </tr>
                            </thead>
                            <tbody>
                                {filteredVendors.length === 0 ? (
                                    <tr>
                                        <td colSpan="5" style={{ textAlign: 'center', padding: '100px 0' }}>
                                            <Store size={48} color="#e2e8f0" style={{ marginBottom: '20px' }} />
                                            <h3 style={{ fontSize: '1.5rem', fontWeight: '900', color: '#0f172a', marginBottom: '8px' }}>No Nodes Detected</h3>
                                            <p style={{ color: '#64748b', fontWeight: '600', marginBottom: '24px' }}>The logistics grid is currently empty or your search is too specific.</p>
                                            <button onClick={fetchVendors} className="btn-primary" style={{ display: 'inline-flex', gap: '8px', alignItems: 'center' }}>
                                                <RefreshCw size={18} /> RECONNECT TO GRID
                                            </button>
                                        </td>
                                    </tr>
                                ) : filteredVendors.map(v => (
                                    <tr key={v.id} style={{ borderBottom: '1px solid #f1f5f9', background: selectedVendorNode?.id === v.id ? '#f0f9ff' : 'transparent' }} className="table-row-hover">
                                        <td data-label="Vendor Info" style={{ padding: '16px' }} onClick={() => handleEditVendor(v)}>
                                            <div style={{ display: 'flex', alignItems: 'center', gap: '12px', cursor: 'pointer' }}>
                                                <div style={{ width: '40px', height: '40px', borderRadius: '10px', background: '#FFD600', display: 'grid', placeItems: 'center', fontSize: '1rem', fontWeight: '900', color: '#0F172A' }}>
                                                    {v.name?.[0] || 'V'}
                                                </div>
                                                <div>
                                                    <div style={{ fontSize: '0.875rem', fontWeight: '700', color: '#0f172a' }}>{v.name}</div>
                                                    <div style={{ fontSize: '0.75rem', color: '#64748b', display: 'flex', alignItems: 'center', gap: '4px' }}>
                                                        <Store size={10} /> {v.email || 'No email linked'}
                                                    </div>
                                                </div>
                                            </div>
                                        </td>
                                        <td data-label="Manager" style={{ padding: '16px' }}>
                                            <div style={{ fontWeight: '700', color: '#0F172A', fontSize: '0.875rem' }}>{v.manager}</div>
                                            <div style={{ fontSize: '0.75rem', color: '#FF9500', fontWeight: '900' }}>{v.cuisine_type}</div>
                                        </td>
                                        <td data-label="Rating" style={{ padding: '16px' }}>
                                            <div style={{ display: 'flex', alignItems: 'center', gap: '4px', background: '#FEF9C3', padding: '4px 8px', borderRadius: '8px', width: 'fit-content' }}>
                                                <Star size={14} color="#A16207" fill="#A16207" />
                                                <span style={{ fontWeight: '900', color: '#A16207', fontSize: '0.85rem' }}>{v.rating?.toFixed(1) || '5.0'}</span>
                                            </div>
                                        </td>

                                        <td data-label="Earnings" style={{ padding: '16px' }}>
                                            <div style={{ fontWeight: '900', color: '#166534', fontSize: '0.9rem' }}>₹{v.pending_payout?.toLocaleString() || '0'}</div>
                                            <div style={{ fontSize: '0.7rem', color: '#64748b' }}>Pending Payout</div>
                                        </td>
                                        <td data-label="Status" style={{ padding: '16px' }}>
                                            <Toggle
                                                active={v.status === 'ONLINE'}
                                                onToggle={() => toggleStatus(v)}
                                            />
                                        </td>
                                        <td data-label="Control" style={{ padding: '16px' }}>
                                            <div style={{ display: 'flex', gap: '12px', alignItems: 'center' }}>
                                                <button 
                                                    onClick={() => handleSelectVendor(v)}
                                                    style={{ 
                                                        padding: '6px 12px', 
                                                        borderRadius: '8px', 
                                                        background: selectedVendorNode?.id === v.id ? '#0f172a' : '#f1f5f9', 
                                                        color: selectedVendorNode?.id === v.id ? '#ffd600' : '#0f172a', 
                                                        border: 'none', 
                                                        fontSize: '0.7rem', 
                                                        fontWeight: '900', 
                                                        cursor: 'pointer' 
                                                    }}
                                                >
                                                    MENU
                                                </button>
                                                <button 
                                                    onClick={() => handleEditVendor(v)}
                                                    style={{ 
                                                        padding: '6px 12px', 
                                                        borderRadius: '8px', 
                                                        background: '#f1f5f9', 
                                                        color: '#0f172a', 
                                                        border: 'none', 
                                                        fontSize: '0.7rem', 
                                                        fontWeight: '900', 
                                                        cursor: 'pointer' 
                                                    }}
                                                >
                                                    EDIT
                                                </button>
                                                <button onClick={() => handleDelete(v.id)} style={{ width: '32px', height: '32px', borderRadius: '6px', background: '#fff1f1', border: 'none', display: 'grid', placeItems: 'center', cursor: 'pointer' }}><X size={14} color="#ef4444" /></button>
                                            </div>
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}
            </div>

            {/* Vendor Menu Section */}
            {selectedVendorNode && (
                <div id="vendor-menu-section" className="glass-panel" style={{ marginTop: '40px', padding: '40px', background: 'white' }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '32px' }}>
                        <div>
                            <h2 style={{ fontSize: '1.5rem', fontWeight: '900', color: '#0F172A' }}>Menu Management: {selectedVendorNode.name}</h2>
                            <p style={{ color: '#64748B', fontSize: '0.9rem', marginTop: '4px' }}>Add and manage items for this specific vendor station.</p>
                        </div>
                        <button 
                            onClick={() => {
                                setEditingProduct(null);
                                setProductModalOpen(true);
                            }}
                            className="btn-primary"
                        >
                            <Plus size={18} /> Add New Item
                        </button>
                    </div>

                    {loadMenu ? (
                        <div style={{ textAlign: 'center', padding: '40px' }}>Loading menu items...</div>
                    ) : vendorItems.length === 0 ? (
                        <div style={{ textAlign: 'center', padding: '80px', background: '#f8fafc', borderRadius: '24px' }}>
                            <div style={{ opacity: 0.5, marginBottom: '16px' }}>📦</div>
                            <h3 style={{ fontWeight: '800' }}>No items added yet</h3>
                            <p style={{ color: '#64748b' }}>Start building the menu for this vendor.</p>
                        </div>
                    ) : (
                        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))', gap: '24px' }}>
                            {vendorItems.map(item => (
                                <div key={item.id} className="glass-panel" style={{ padding: '0', overflow: 'hidden', border: '1px solid #f1f5f9' }}>
                                    <div style={{ height: '160px', position: 'relative' }}>
                                        <img src={item.image_url || 'https://via.placeholder.com/300x200?text=No+Image'} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                                        <div style={{ position: 'absolute', top: '10px', left: '10px', background: item.is_veg ? '#10b981' : '#ef4444', color: 'white', padding: '4px 8px', borderRadius: '6px', fontSize: '0.65rem', fontWeight: '900' }}>
                                            {item.is_veg ? 'VEG' : 'NON-VEG'}
                                        </div>
                                    </div>
                                    <div style={{ padding: '20px' }}>
                                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                                            <h4 style={{ fontWeight: '800', color: '#0f172a', fontSize: '1rem', margin: 0 }}>{item.name}</h4>
                                            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: '4px' }}>
                                                <span style={{ fontWeight: '900', color: '#166534' }}>₹{item.price}</span>
                                                <div style={{ 
                                                    background: item.item_type === 'POPULAR_ITEM' ? '#FFD600' : '#F1F5F9', 
                                                    color: '#0F172A', 
                                                    padding: '2px 8px', 
                                                    borderRadius: '6px', 
                                                    fontSize: '0.65rem', 
                                                    fontWeight: '900',
                                                    border: item.item_type === 'POPULAR_ITEM' ? '1px solid #EAB308' : '1px solid #E2E8F0'
                                                }}>
                                                    {item.item_type === 'POPULAR_ITEM' ? '⭐ POPULAR' : 'NORMAL'}
                                                </div>
                                            </div>
                                        </div>
                                        <p style={{ fontSize: '0.75rem', color: '#64748b', marginTop: '8px', minHeight: '36px' }}>{item.description || 'No description provided.'}</p>
                                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginTop: '16px', position: 'relative', zIndex: 10 }}>
                                            <div style={{ display: 'flex', gap: '8px' }}>
                                                <Toggle 
                                                    active={item.is_available} 
                                                    onToggle={() => {
                                                        console.log("⚡ Toggle Action ->", item.id);
                                                        toggleProductAvailability(item.id, item.is_available);
                                                    }}
                                                    label={item.is_available ? 'In Stock' : 'Out'}
                                                    disabled={processingId === `toggle-${item.id}`}
                                                />
                                                <Toggle 
                                                    active={item.item_type === 'POPULAR_ITEM'} 
                                                    onToggle={async () => {
                                                        const newType = item.item_type === 'POPULAR_ITEM' ? 'NORMAL_VENDOR_ITEM' : 'POPULAR_ITEM';
                                                        const original = [...vendorItems];
                                                        setVendorItems(prev => prev.map(p => p.id === item.id ? { ...p, item_type: newType } : p));
                                                        const { error } = await adminSupabase.from('products').update({ item_type: newType }).eq('id', item.id);
                                                        if (error) setVendorItems(original);
                                                    }}
                                                    label="POPULAR"
                                                />
                                            </div>
                                            <div style={{ display: 'flex', gap: '4px' }}>
                                                <button 
                                                    type="button"
                                                    title="Edit Item"
                                                    onClick={(e) => { 
                                                        e.stopPropagation(); 
                                                        console.log("✏️ Edit Action ->", item.id);
                                                        setEditingProduct(item); 
                                                        setProductModalOpen(true); 
                                                    }}
                                                    style={{ background: '#f8fafc', border: '1px solid #e2e8f0', color: '#64748b', cursor: 'pointer', padding: '8px', borderRadius: '10px', display: 'flex', alignItems: 'center', justifyContent: 'center' }}
                                                >
                                                    <Tag size={16} />
                                                </button>
                                                <button 
                                                    type="button"
                                                    title="Delete Item"
                                                    onClick={(e) => { 
                                                        e.stopPropagation(); 
                                                        console.log("🗑️ Delete Action ->", item.id);
                                                        handleProductDelete(item.id); 
                                                    }}
                                                    style={{ background: '#fdf2f2', border: '1px solid #fee2e2', color: '#ef4444', cursor: 'pointer', padding: '8px', borderRadius: '10px', display: 'flex', alignItems: 'center', justifyContent: 'center' }}
                                                    disabled={processingId === item.id}
                                                >
                                                    <Trash2 size={16} style={{ opacity: processingId === item.id ? 0.5 : 1 }} />
                                                </button>
                                            </div>
                                        </div>
                                    </div>
                                </div>
                            ))}
                        </div>
                    )}
                </div>
            )}

            {/* Modal Overlay */}
            <AnimatePresence>
                {isModalOpen && (
                    <div style={{ position: 'fixed', inset: 0, zIndex: 9999, display: 'grid', placeItems: 'center', padding: '20px' }}>
                        <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} onClick={() => setIsModalOpen(false)} style={{ position: 'absolute', inset: 0, background: 'rgba(15, 23, 42, 0.4)', backdropFilter: 'blur(10px)' }} />
                        <motion.div initial={{ opacity: 0, y: 30, scale: 0.95 }} animate={{ opacity: 1, y: 0, scale: 1 }} exit={{ opacity: 0, y: 30, scale: 0.95 }} style={{ position: 'relative', background: 'white', width: '100%', maxWidth: '800px', borderRadius: '40px', padding: '0', boxShadow: '0 50px 100px -20px rgba(15,23,42,0.25)', maxHeight: '90vh', overflowY: 'auto', display: 'flex', flexDirection: 'column' }}>

                            <div style={{ padding: '40px 40px 0 40px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                                <h2 style={{ fontSize: '1.6rem', fontWeight: '900', color: '#0f172a', letterSpacing: '-0.03em' }}>{editingVendor ? 'Edit Vendor' : 'Add Vendor'}</h2>
                                <button onClick={() => { setIsModalOpen(false); setEditingVendor(null); }} style={{ background: '#f1f5f9', border: 'none', padding: '10px', borderRadius: '14px', cursor: 'pointer' }}><X size={20} /></button>
                            </div>

                            <div style={{ padding: '40px' }}>
                                <form onSubmit={handleCreateVendor} className="modal-content-grid" style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px' }}>
                                    <div style={{ gridColumn: 'span 2', display: 'flex', justifyContent: 'space-between', alignItems: 'center', background: '#f8fafc', padding: '16px', borderRadius: '16px', border: '1px solid #e2e8f0', marginBottom: '10px' }}>
                                        <div>
                                            <label style={{ fontSize: '0.85rem', fontWeight: '800', color: '#0f172a', marginBottom: '4px', display: 'block' }}>Vendor Name</label>
                                            <input type="text" value={newVendor.name} onChange={e => setNewVendor({ ...newVendor, name: e.target.value })} placeholder="e.g. Royal Curry" required style={{ width: '280px', padding: '10px', borderRadius: '8px', border: '1px solid #e2e8f0', outline: 'none', fontSize: '0.95rem' }} />
                                        </div>
                                        {editingVendor && (
                                            <div style={{ textAlign: 'right' }}>
                                                <label style={{ fontSize: '0.75rem', fontWeight: '800', color: '#64748b', marginBottom: '8px', display: 'block', textTransform: 'uppercase' }}>Shop Status</label>
                                                <Toggle
                                                    active={vendors.find(v => v.id === editingVendor)?.status === 'ONLINE'}
                                                    onToggle={() => toggleStatus(vendors.find(v => v.id === editingVendor))}
                                                    label={vendors.find(v => v.id === editingVendor)?.status}
                                                />
                                            </div>
                                        )}
                                    </div>

                                    <div style={{ gridColumn: 'span 2', background: '#fef2f2', padding: '16px', borderRadius: '12px', border: '1px solid #fee2e2', marginBottom: '10px' }}>
                                        <label style={{ fontSize: '0.8rem', fontWeight: '800', color: '#dc2626', marginBottom: '8px', display: 'block', textTransform: 'uppercase' }}>Login Credentials</label>
                                        <div style={{ display: 'flex', gap: '12px' }}>
                                            <div style={{ flex: 1 }}>
                                                <label style={{ fontSize: '0.75rem', fontWeight: '800', color: '#64748b', marginBottom: '4px', display: 'block' }}>Email Address</label>
                                                <input type="email" value={newVendor.email || ''} onChange={e => setNewVendor({ ...newVendor, email: e.target.value })} placeholder="Vendor Email" style={{ width: '100%', padding: '10px', borderRadius: '8px', border: '1px solid #e2e8f0', background: 'white', outline: 'none', fontSize: '0.9rem', color: '#0f172a', fontWeight: '700' }} />
                                            </div>
                                            <div style={{ flex: 1 }}>
                                                <input type="tel" value={newVendor.phone} onChange={e => setNewVendor({ ...newVendor, phone: e.target.value })} placeholder="Phone" style={{ width: '100%', padding: '10px', borderRadius: '8px', border: '1px solid #e2e8f0', outline: 'none', fontSize: '0.9rem' }} />
                                            </div>
                                        </div>
                                    </div>

                                    {/* Address & Geocoding */}
                                    <div style={{ gridColumn: 'span 2' }}>
                                        <label style={{ fontSize: '0.85rem', fontWeight: '600', color: '#64748b', marginBottom: '8px', display: 'block' }}>Address</label>
                                        <div style={{ display: 'flex', gap: '8px' }}>
                                            <input type="text" value={newVendor.address} onChange={e => setNewVendor({ ...newVendor, address: e.target.value })} placeholder="Site location" required style={{ flex: 1, padding: '12px', borderRadius: '8px', border: '1px solid #e2e8f0', outline: 'none', fontSize: '1rem' }} />
                                            <button type="button" onClick={geocodeAddress} style={{ padding: '0 20px', borderRadius: '8px', background: '#0F172A', color: 'white', border: 'none', fontWeight: '700', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '8px' }}>
                                                <Search size={16} /> Locate
                                            </button>
                                        </div>
                                    </div>

                                    {/* MAP PREVIEW */}
                                    <div style={{ gridColumn: 'span 2', height: '250px', borderRadius: '16px', overflow: 'hidden', border: '1px solid #e2e8f0' }}>
                                        <MapContainer center={[newVendor.latitude || DEFAULT_CENTER.lat, newVendor.longitude || DEFAULT_CENTER.lng]} zoom={13} style={{ height: '100%', width: '100%' }}>
                                            <TileLayer url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" />
                                            <MapPicker
                                                position={newVendor.latitude ? { lat: newVendor.latitude, lng: newVendor.longitude } : null}
                                                setPosition={(pos) => setNewVendor(prev => ({ ...prev, latitude: pos.lat, longitude: pos.lng }))}
                                            />
                                        </MapContainer>
                                    </div>
                                    <div style={{ gridColumn: 'span 2', textAlign: 'center', fontSize: '0.8rem', color: '#64748b' }}>
                                        Click on the map to fine-tune the location pin.
                                    </div>

                                    <div style={{ gridColumn: 'span 2', display: 'flex', gap: '20px' }}>
                                        <div style={{ flex: 1 }}>
                                            <label style={{ fontSize: '0.85rem', fontWeight: '600', color: '#64748b', marginBottom: '8px', display: 'block' }}>Latitude</label>
                                            <input type="number" step="any" value={newVendor.latitude} readOnly style={{ width: '100%', padding: '12px', borderRadius: '8px', border: '1px solid #e2e8f0', background: '#f8fafc', outline: 'none', fontSize: '1rem' }} />
                                        </div>
                                        <div style={{ flex: 1 }}>
                                            <label style={{ fontSize: '0.85rem', fontWeight: '600', color: '#64748b', marginBottom: '8px', display: 'block' }}>Longitude</label>
                                            <input type="number" step="any" value={newVendor.longitude} readOnly style={{ width: '100%', padding: '12px', borderRadius: '8px', border: '1px solid #e2e8f0', background: '#f8fafc', outline: 'none', fontSize: '1rem' }} />
                                        </div>
                                    </div>

                                    <div>
                                        <label style={{ fontSize: '0.85rem', fontWeight: '600', color: '#64748b', marginBottom: '8px', display: 'block' }}>Cuisine</label>
                                        <select value={newVendor.cuisine} onChange={e => setNewVendor({ ...newVendor, cuisine: e.target.value })} style={{ width: '100%', padding: '12px', borderRadius: '8px', border: '1px solid #e2e8f0', outline: 'none', fontSize: '1rem', background: 'white' }}>
                                            <option>North Indian</option>
                                            <option>South Indian</option>
                                            <option>Pure Vegetarian</option>
                                        </select>
                                    </div>
                                    <div>
                                        <label style={{ fontSize: '0.85rem', fontWeight: '600', color: '#64748b', marginBottom: '8px', display: 'block' }}>Delivery Radius (km)</label>
                                        <input type="number" value={newVendor.delivery_radius_km} onChange={e => setNewVendor({ ...newVendor, delivery_radius_km: e.target.value })} placeholder="10" style={{ width: '100%', padding: '12px', borderRadius: '8px', border: '1px solid #e2e8f0', outline: 'none', fontSize: '1rem' }} />
                                    </div>

                                    <div style={{ gridColumn: 'span 2' }}>
                                        <label style={{ fontSize: '0.85rem', fontWeight: '600', color: '#64748b', marginBottom: '8px', display: 'block' }}>Working Hours</label>
                                        <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                                            <input type="time" value={newVendor.openTime} onChange={e => setNewVendor({ ...newVendor, openTime: e.target.value })} style={{ flex: 1, padding: '10px', borderRadius: '8px', border: '1px solid #e2e8f0' }} />
                                            <span style={{ color: '#94a3b8' }}>to</span>
                                            <input type="time" value={newVendor.closeTime} onChange={e => setNewVendor({ ...newVendor, closeTime: e.target.value })} style={{ flex: 1, padding: '10px', borderRadius: '8px', border: '1px solid #e2e8f0' }} />
                                        </div>
                                    </div>

                                    <div style={{ gridColumn: 'span 2', display: 'flex', gap: '24px', background: '#F8FAFC', padding: '16px', borderRadius: '16px' }}>
                                        <label style={{ display: 'flex', alignItems: 'center', gap: '10px', cursor: 'pointer', flex: 1 }}>
                                            <input
                                                type="checkbox"
                                                checked={newVendor.is_pure_veg}
                                                onChange={e => setNewVendor({ ...newVendor, is_pure_veg: e.target.checked })}
                                                style={{ width: '20px', height: '20px', accentColor: '#10B981' }}
                                            />
                                            <span style={{ fontSize: '0.9rem', fontWeight: '700', color: '#0F172A' }}>Pure Veg Outlet</span>
                                        </label>
                                        <label style={{ display: 'flex', alignItems: 'center', gap: '10px', cursor: 'pointer', flex: 1 }}>
                                            <input
                                                type="checkbox"
                                                checked={newVendor.has_offers}
                                                onChange={e => setNewVendor({ ...newVendor, has_offers: e.target.checked })}
                                                style={{ width: '20px', height: '20px', accentColor: '#F59E0B' }}
                                            />
                                            <span style={{ fontSize: '0.9rem', fontWeight: '700', color: '#0F172A' }}>Active Offers</span>
                                        </label>
                                    </div>
                                    <div style={{ gridColumn: 'span 2' }}>
                                        <ImageUpload
                                            label="Restaurant Banner"
                                            value={newVendor.banner_url}
                                            onUpload={(url) => setNewVendor({ ...newVendor, banner_url: url })}
                                            folder="vendors"
                                        />
                                    </div>
                                    <div style={{ gridColumn: 'span 2', display: 'flex', gap: '16px', marginTop: '24px' }}>
                                        <button type="button" onClick={() => setIsModalOpen(false)} style={{ flex: 1, padding: '14px', borderRadius: '14px', border: '2px solid #F1F5F9', color: '#0F172A', fontWeight: '800' }}>Cancel</button>
                                        <button type="submit" style={{ flex: 1, padding: '14px', borderRadius: '14px', border: 'none', background: '#FFD600', color: '#0F172A', fontWeight: '800', boxShadow: '0 8px 16px rgba(255, 214, 0, 0.3)' }}>Deploy Partner</button>
                                    </div>
                                </form>
                            </div>
                        </motion.div>
                    </div>
                )
                }
            </AnimatePresence >

            {/* Product Modal Overlay */}
            <AnimatePresence>
                {productModalOpen && (
                    <div style={{ position: 'fixed', inset: 0, zIndex: 10000, display: 'grid', placeItems: 'center', padding: '20px' }}>
                        <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} onClick={() => setProductModalOpen(false)} style={{ position: 'absolute', inset: 0, background: 'rgba(15, 23, 42, 0.6)', backdropFilter: 'blur(10px)' }} />
                        <motion.div initial={{ opacity: 0, scale: 0.9 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.9 }} style={{ position: 'relative', background: 'white', width: '100%', maxWidth: '500px', borderRadius: '32px', padding: '40px', boxShadow: '0 40px 80px rgba(0,0,0,0.3)', maxHeight: '90vh', overflowY: 'auto' }}>
                            <h3 style={{ fontSize: '1.4rem', fontWeight: '900', color: '#0F172A', marginBottom: '24px' }}>{editingProduct ? 'Edit Item' : 'Add Item'}</h3>
                            
                            <div style={{ display: 'grid', gap: '16px' }}>
                                <div>
                                    <label style={{ fontSize: '0.8rem', fontWeight: '800', color: '#64748b' }}>Item Name</label>
                                    <input type="text" value={productForm.name} onChange={e => setProductForm({...productForm, name: e.target.value})} placeholder="e.g. Garlic Naan" style={{ width: '100%', padding: '12px', borderRadius: '10px', border: '1px solid #e2e8f0', color: '#0F172A', fontWeight: '700' }} />
                                </div>
                                <div>
                                    <label style={{ fontSize: '0.8rem', fontWeight: '800', color: '#64748b' }}>Description</label>
                                    <textarea value={productForm.description} onChange={e => setProductForm({...productForm, description: e.target.value})} placeholder="Describe the flavors..." style={{ width: '100%', padding: '12px', borderRadius: '10px', border: '1px solid #e2e8f0', minHeight: '80px', fontFamily: 'inherit' }} />
                                </div>
                                <div>
                                    <label style={{ fontSize: '0.8rem', fontWeight: '800', color: '#64748b' }}>Price (₹)</label>
                                    <input type="number" value={productForm.price} onChange={e => setProductForm({...productForm, price: e.target.value})} style={{ width: '100%', padding: '12px', borderRadius: '10px', border: '1px solid #e2e8f0' }} />
                                </div>
                                <div>
                                    <label style={{ fontSize: '0.8rem', fontWeight: '800', color: '#64748b' }}>Category</label>
                                    <select value={productForm.category_id} onChange={e => setProductForm({...productForm, category_id: e.target.value})} style={{ width: '100%', padding: '12px', borderRadius: '10px', border: '1px solid #e2e8f0', background: 'white' }}>
                                        <option value="">Select Category</option>
                                        {categories.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
                                    </select>
                                </div>
                                <div>
                                    <label style={{ fontSize: '0.85rem', fontWeight: '900', color: '#0F172A', marginBottom: '12px', display: 'block', textTransform: 'uppercase' }}>Select Item Type (Required)</label>
                                    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px' }}>
                                        <button
                                            type="button"
                                            onClick={() => setProductForm({ ...productForm, item_type: 'POPULAR_ITEM' })}
                                            style={{
                                                padding: '16px',
                                                borderRadius: '16px',
                                                border: productForm.item_type === 'POPULAR_ITEM' ? '3px solid #FFD600' : '2px solid #E2E8F0',
                                                background: productForm.item_type === 'POPULAR_ITEM' ? '#FFFBEB' : 'white',
                                                cursor: 'pointer',
                                                textAlign: 'center',
                                                transition: 'all 0.2s ease'
                                            }}
                                        >
                                            <div style={{ fontSize: '1rem', fontWeight: '900', color: '#0F172A' }}>Popular Item</div>
                                            <div style={{ fontSize: '0.7rem', color: '#64748B', marginTop: '4px' }}>Shared across vendors</div>
                                        </button>
                                        <button
                                            type="button"
                                            onClick={() => setProductForm({ ...productForm, item_type: 'NORMAL_VENDOR_ITEM' })}
                                            style={{
                                                padding: '16px',
                                                borderRadius: '16px',
                                                border: (productForm.item_type === 'NORMAL_VENDOR_ITEM' || !productForm.item_type) ? '3px solid #0F172A' : '2px solid #E2E8F0',
                                                background: (productForm.item_type === 'NORMAL_VENDOR_ITEM' || !productForm.item_type) ? '#F8FAFC' : 'white',
                                                cursor: 'pointer',
                                                textAlign: 'center',
                                                transition: 'all 0.2s ease'
                                            }}
                                        >
                                            <div style={{ fontSize: '1rem', fontWeight: '900', color: '#0F172A' }}>Normal Item</div>
                                            <div style={{ fontSize: '0.7rem', color: '#64748B', marginTop: '4px' }}>This vendor only</div>
                                        </button>
                                    </div>
                                </div>
                                <div>
                                    <ImageUpload
                                        label="Item Visual"
                                        value={productForm.image_url}
                                        onUpload={(url) => setProductForm({ ...productForm, image_url: url })}
                                        folder="products"
                                    />
                                </div>
                                <div style={{ display: 'flex', gap: '20px' }}>
                                    <label style={{ display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer' }}>
                                        <input type="checkbox" checked={productForm.is_veg} onChange={e => setProductForm({...productForm, is_veg: e.target.checked})} />
                                        <span style={{ fontSize: '0.9rem', fontWeight: '700' }}>Veg</span>
                                    </label>
                                    <label style={{ display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer' }}>
                                        <input type="checkbox" checked={productForm.is_available} onChange={e => setProductForm({...productForm, is_available: e.target.checked})} />
                                        <span style={{ fontSize: '0.9rem', fontWeight: '700' }}>Available</span>
                                    </label>
                                </div>
                            </div>

                            <div style={{ display: 'flex', gap: '12px', marginTop: '32px' }}>
                                <button onClick={() => setProductModalOpen(false)} style={{ flex: 1, padding: '12px', borderRadius: '12px', border: 'none', background: '#f1f5f9', fontWeight: '800' }}>Cancel</button>
                                <button 
                                    type="button"
                                    onClick={(e) => {
                                        e.preventDefault();
                                        e.stopPropagation();
                                        handleProductSave({ ...productForm, id: editingProduct?.id });
                                    }}
                                    disabled={!!processingId}
                                    style={{ flex: 1, padding: '14px', borderRadius: '14px', border: 'none', background: '#FFD600', color: '#0F172A', fontWeight: '800', opacity: processingId ? 0.7 : 1, cursor: processingId ? 'not-allowed' : 'pointer' }}
                                >
                                    {processingId ? 'Processing...' : (editingProduct ? 'Save Changes' : 'Add to Menu')}
                                </button>
                            </div>
                        </motion.div>
                    </div>
                )}
            </AnimatePresence>

            <style>{`
                .table-row-hover:hover {
                    background: #F4F7FE !important;
                    transform: scale(1.002);
                }
            `}</style>
        </div >
    );
};

export default Vendors;
