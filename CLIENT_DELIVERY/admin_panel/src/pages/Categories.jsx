import React, { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import {
    Plus, Search, Edit2, Trash2, Loader2,
    X, Image as ImageIcon, CheckCircle, Smartphone
} from 'lucide-react';
import { supabase, adminSupabase } from '../supabase';
import { COLLECTIONS } from '../constants';
import { toast } from 'react-hot-toast';
import ImageUpload from '../components/ImageUpload';
import './Categories-Beautiful.css';

const Categories = () => {
    const [categories, setCategories] = useState([]);
    const [loading, setLoading] = useState(true);
    const [searchTerm, setSearchTerm] = useState('');
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [isEditing, setIsEditing] = useState(false);
    const [selectedCategory, setSelectedCategory] = useState(null);

    const [formData, setFormData] = useState({
        name: '',
        image_url: ''
    });

    useEffect(() => {
        fetchCategories();
        const sub = supabase.channel('categories-sync')
            .on('postgres_changes', { event: '*', schema: 'public', table: COLLECTIONS.CATEGORIES }, fetchCategories)
            .subscribe();
        return () => sub.unsubscribe();
    }, []);

    const fetchCategories = async () => {
        try {
            if (categories.length === 0) setLoading(true);
            const { data, error } = await adminSupabase
                .from(COLLECTIONS.CATEGORIES)
                .select('*')
                .order('created_at', { ascending: false });

            if (error) throw error;
            
            setCategories(prev => {
                const isSame = JSON.stringify(prev) === JSON.stringify(data);
                return isSame ? prev : (data || []);
            });
        } catch (error) {
            console.error('Error fetching categories:', error);
        } finally {
            setLoading(false);
        }
    };

    const handleSave = async (e) => {
        e.preventDefault();
        const toastId = toast.loading(isEditing ? 'Updating category...' : 'Adding category...');
        const originalCategories = [...categories];

        try {
            const payload = {
                name: formData.name,
                image_url: formData.image_url,
                is_active: true,
                priority: 0
            };

            // OPTIMISTIC UPDATE
            if (isEditing) {
                setCategories(prev => prev.map(c => 
                    c.id === selectedCategory.id ? { ...c, ...payload } : c
                ));
            } else {
                const tempCat = { ...payload, id: 'temp-' + Date.now() };
                setCategories(prev => [tempCat, ...prev]);
            }

            setIsModalOpen(false); // Close modal instantly

            if (isEditing) {
                const { error } = await adminSupabase
                    .from(COLLECTIONS.CATEGORIES)
                    .update(payload)
                    .eq('id', selectedCategory.id);
                if (error) throw error;
                toast.success('Category updated instantly', { id: toastId });
            } else {
                const { data, error } = await adminSupabase
                    .from(COLLECTIONS.CATEGORIES)
                    .insert([payload])
                    .select();
                if (error) throw error;
                
                if (data && data[0]) {
                    setCategories(prev => prev.map(c => c.id.startsWith('temp-') ? data[0] : c));
                }
                toast.success('Category deployed', { id: toastId });
            }

            setFormData({ name: '', image_url: '' });
            fetchCategories(); // Background sync
        } catch (error) {
            console.error('Error saving category:', error);
            setCategories(originalCategories); // Rollback
            toast.error('Sync Error: ' + error.message, { id: toastId });
        }
    };

    const handleDelete = async (id) => {
        if (!window.confirm('This will remove this category cluster from the system. Proceed?')) return;

        const originalCategories = [...categories];
        setCategories(prev => prev.filter(c => c.id !== id));
        toast.success('Category removed from local grid');

        try {
            const { error } = await adminSupabase
                .from(COLLECTIONS.CATEGORIES)
                .delete()
                .eq('id', id);

            if (error) {
                setCategories(originalCategories); // Rollback
                toast.error('Delete Failed: ' + error.message);
            }
        } catch (error) {
            setCategories(originalCategories);
            toast.error('Network Disconnection');
        }
    };

    const openEditModal = (category) => {
        setSelectedCategory(category);
        setFormData({
            name: category.name || '',
            image_url: category.image_url || ''
        });
        setIsEditing(true);
        setIsModalOpen(true);
    };

    const openAddModal = () => {
        setSelectedCategory(null);
        setFormData({ name: '', image_url: '' });
        setIsEditing(false);
        setIsModalOpen(true);
    };

    const filteredCategories = categories.filter(c =>
        c.name?.toLowerCase().includes(searchTerm.toLowerCase())
    );

    return (
        <div className="categories-beautiful-page">
            <header className="categories-header">
                <div>
                    <h1>Categories</h1>
                    <p>Manage food categories and their display order.</p>
                </div>
                <div className="page-actions">
                    <button
                        className="new-category-btn"
                        onClick={openAddModal}
                    >
                        <Plus size={20} /> Deploy Category
                    </button>
                </div>
            </header>

            <div className="categories-search-bar">
                <div className="search-input-wrapper">
                    <Search size={20} />
                    <input
                        type="text"
                        placeholder="Search categories..."
                        value={searchTerm}
                        onChange={(e) => setSearchTerm(e.target.value)}
                    />
                </div>
                <div className="categories-stats">
                    <span>Total: {categories.length}</span>
                    <span>Active: {categories.length}</span>
                </div>
            </div>

            {loading ? (
                <div className="loading-state">
                    <Loader2 className="animate-spin" size={40} />
                </div>
            ) : (
                <div className="categories-grid">
                    {filteredCategories.map((category, idx) => (
                        <motion.div
                            key={category.id}
                            className="category-card"
                            initial={{ opacity: 0, y: 20 }}
                            animate={{ opacity: 1, y: 0 }}
                            whileHover={{ y: -5 }}
                            style={{ position: 'relative' }}
                        >
                            <div className="category-image-wrapper">
                                {category.image_url ? (
                                    <img src={category.image_url} alt={category.name} />
                                ) : (
                                    <div className="category-placeholder">
                                        <ImageIcon size={40} />
                                    </div>
                                )}
                                <div className="category-badge">CLUSTER ACTIVE</div>
                            </div>
                            <div className="category-info" style={{ width: '100%' }}>
                                <div style={{ position: 'relative', marginBottom: '8px' }}>
                                    <h3 style={{ margin: '0 auto', fontSize: '1.25rem', fontWeight: '800', color: '#0f172a' }}>{category.name}</h3>
                                    <span style={{ position: 'absolute', top: '4px', right: '0', fontSize: '0.7rem', fontWeight: '800', color: '#94a3b8' }}>#{idx + 1}</span>
                                </div>
                                <p style={{ fontSize: '0.85rem', color: '#64748b', margin: '0 auto', maxWidth: '90%' }}>Managing operational segment for platform inventory.</p>
                            </div>
                            <div className="category-actions">
                                <button
                                    className="add-item-btn"
                                    onClick={() => window.location.href = `/menu?category=${category.id}`}
                                    style={{ flex: 1, background: '#F1F5F9', border: 'none', padding: '10px', borderRadius: '10px', fontWeight: '800', fontSize: '0.75rem', color: '#0F172A', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '6px' }}
                                >
                                    <Plus size={14} /> Add Item
                                </button>
                                <button
                                    className="edit-btn"
                                    onClick={() => openEditModal(category)}
                                    style={{ flex: 1 }}
                                >
                                    <Edit2 size={16} /> Edit
                                </button>
                                <button
                                    className="delete-icon-btn"
                                    onClick={() => handleDelete(category.id)}
                                >
                                    <Trash2 size={18} />
                                </button>
                            </div>
                        </motion.div>
                    ))}
                    {filteredCategories.length === 0 && (
                        <div className="empty-state-card" style={{ gridColumn: '1 / -1' }}>
                            <ImageIcon size={60} />
                            <h3>No categories found</h3>
                            <p>Create your first category to get started</p>
                        </div>
                    )}
                </div>
            )}

            <AnimatePresence>
                {isModalOpen && (
                    <div className="modal-overlay">
                        <motion.div
                            className="modal-content"
                            initial={{ opacity: 0, scale: 0.95 }}
                            animate={{ opacity: 1, scale: 1 }}
                            exit={{ opacity: 0, scale: 0.95 }}
                        >
                            <div className="modal-header">
                                <h2>{isEditing ? 'Edit Category' : 'Add New Category'}</h2>
                                <button className="close-btn" onClick={() => setIsModalOpen(false)}>
                                    <X size={24} />
                                </button>
                            </div>

                            <form onSubmit={handleSave}>
                                <div className="form-group">
                                    <label>Category Name</label>
                                    <input
                                        type="text"
                                        required
                                        value={formData.name}
                                        onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                                        placeholder="e.g. Biryani, Curries"
                                    />
                                </div>

                                <div className="form-group">
                                    <label>Category Image</label>
                                    <ImageUpload
                                        value={formData.image_url}
                                        onChange={(url) => setFormData({ ...formData, image_url: url })}
                                        folder="categories"
                                    />
                                </div>

                                <div className="modal-footer">
                                    <button
                                        type="button"
                                        className="cancel-btn"
                                        onClick={() => setIsModalOpen(false)}
                                    >
                                        Cancel
                                    </button>
                                    <button type="submit" className="save-btn">
                                        {isEditing ? 'Save Changes' : 'Create Category'}
                                    </button>
                                </div>
                            </form>
                        </motion.div>
                    </div>
                )}
            </AnimatePresence>
        </div>
    );
};

export default Categories;
