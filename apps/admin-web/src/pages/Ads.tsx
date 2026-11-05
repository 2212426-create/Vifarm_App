import React, { useState, useEffect } from 'react';
import { useAuth } from '../components/auth-provider';
import {
  Megaphone,
  Plus,
  Play,
  Pause,
  Trash2,
  Edit2,
  RefreshCw,
  TrendingUp,
  Eye,
  MousePointerClick,
  Percent,
  X,
  ExternalLink,
  DollarSign
} from 'lucide-react';
import { db, collection, onSnapshot, doc, addDoc, updateDoc, deleteDoc, query, where, getCountFromServer } from '../lib/firebase';
import type { Ad, AdStatus } from '../types';
import { clsx } from 'clsx';

export function Ads() {
  const { user: authUser } = useAuth();

  // Cloudinary settings
  const [cloudName, setCloudName] = useState(() => localStorage.getItem('cloudinary_cloud_name') || (import.meta.env.VITE_CLOUDINARY_CLOUD_NAME as string) || '');
  const [uploadPreset, setUploadPreset] = useState(() => localStorage.getItem('cloudinary_upload_preset') || (import.meta.env.VITE_CLOUDINARY_UPLOAD_PRESET as string) || '');
  const [showCloudinaryConfig, setShowCloudinaryConfig] = useState(false);

  // Upload progress states
  const [uploadingVideo, setUploadingVideo] = useState(false);
  const [uploadingThumb, setUploadingThumb] = useState(false);
  const [videoProgress, setVideoProgress] = useState(0);
  const [thumbProgress, setThumbProgress] = useState(0);

  const handleSaveConfig = () => {
    localStorage.setItem('cloudinary_cloud_name', cloudName);
    localStorage.setItem('cloudinary_upload_preset', uploadPreset);
    setShowCloudinaryConfig(false);
    alert('Đã lưu cấu hình Cloudinary vào LocalStorage!');
  };

  const handleUploadFile = async (file: File, type: 'video' | 'image') => {
    if (!cloudName || !uploadPreset) {
      alert("Vui lòng cấu hình Cloudinary Cloud Name và Upload Preset trước!");
      setShowCloudinaryConfig(true);
      return;
    }

    const setUploading = type === 'video' ? setUploadingVideo : setUploadingThumb;
    const setProgress = type === 'video' ? setVideoProgress : setThumbProgress;
    const setUrl = type === 'video' ? setVideoUrl : setThumbnail;

    setUploading(true);
    setProgress(0);

    const formData = new FormData();
    formData.append('file', file);
    formData.append('upload_preset', uploadPreset);

    try {
      const xhr = new XMLHttpRequest();
      xhr.open('POST', `https://api.cloudinary.com/v1_1/${cloudName}/${type === 'video' ? 'video' : 'image'}/upload`);

      xhr.upload.onprogress = (event) => {
        if (event.lengthComputable) {
          const percent = Math.round((event.loaded / event.total) * 100);
          setProgress(percent);
        }
      };

      xhr.onload = () => {
        setUploading(false);
        if (xhr.status === 200) {
          const response = JSON.parse(xhr.responseText);
          setUrl(response.secure_url);
        } else {
          let errMsg = xhr.statusText;
          try {
            const errResponse = JSON.parse(xhr.responseText);
            errMsg = errResponse.error?.message || errMsg;
          } catch(e) {}
          alert(`Lỗi upload Cloudinary: ${errMsg}`);
        }
      };

      xhr.onerror = () => {
        setUploading(false);
        alert("Có lỗi kết nối xảy ra khi upload lên Cloudinary!");
      };

      xhr.send(formData);
    } catch (err) {
      console.error("Cloudinary upload error:", err);
      setUploading(false);
      alert("Lỗi xảy ra trong quá trình upload!");
    }
  };
  const [ads, setAds] = useState<Ad[]>([]);
  const [loading, setLoading] = useState(true);
  const [stats, setStats] = useState<Record<string, { impressions: number; views: number; clicks: number }>>({});
  
  // Modal states
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [editingAd, setEditingAd] = useState<Ad | null>(null);
  
  // Form states
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [videoUrl, setVideoUrl] = useState('');
  const [thumbnail, setThumbnail] = useState('');
  const [advertiserName, setAdvertiserName] = useState('');
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');
  const [budget, setBudget] = useState(10000000);
  const [priority, setPriority] = useState(3);
  const [status, setStatus] = useState<AdStatus>('active');
  const [ctaText, setCtaText] = useState('Tìm hiểu thêm');
  const [targetUrl, setTargetUrl] = useState('');

  useEffect(() => {
    // Listen to active/paused ads
    const unsubAds = onSnapshot(collection(db, 'ads'), (snapshot) => {
      const adList: Ad[] = [];
      snapshot.forEach((doc) => {
        const data = doc.data();
        adList.push({
          id: doc.id,
          title: data.title || '',
          description: data.description || '',
          videoUrl: data.videoUrl || data.videoUri || '',
          thumbnail: data.thumbnail || data.thumbnailUri || '',
          advertiserName: data.advertiserName || data.sponsorName || 'Tài trợ',
          advertiserId: data.advertiserId || 'admin',
          startDate: data.startDate || Date.now(),
          endDate: data.endDate || (Date.now() + 30 * 24 * 60 * 60 * 1000),
          budget: data.budget || 0,
          priority: data.priority || 1,
          status: data.status || 'active',
          ctaText: data.ctaText || 'Tìm hiểu thêm',
          targetUrl: data.targetUrl || '',
        });
      });
      setAds(adList);
      setLoading(false);
    }, (error) => {
      console.error("Error fetching ads: ", error);
      setLoading(false);
    });

    return () => unsubAds();
  }, []);

  // Listen to counts from server in real-time when ads list changes
  useEffect(() => {
    if (ads.length === 0) return;

    const unsubs: (() => void)[] = [];

    // Initialize metrics state for all ads to prevent blank states
    const initialMetrics: Record<string, { impressions: number; views: number; clicks: number }> = {};
    ads.forEach(ad => {
      initialMetrics[ad.id] = stats[ad.id] || { impressions: 0, views: 0, clicks: 0 };
    });
    setStats(initialMetrics);

    ads.forEach((ad) => {
      const qImp = query(collection(db, 'ad_impressions'), where('adId', '==', ad.id));
      const qView = query(collection(db, 'ad_views'), where('adId', '==', ad.id));
      const qClick = query(collection(db, 'ad_clicks'), where('adId', '==', ad.id));

      const unsubImp = onSnapshot(qImp, (snap) => {
        setStats(prev => ({
          ...prev,
          [ad.id]: {
            ...prev[ad.id],
            impressions: snap.size
          }
        }));
      }, (err) => {
        console.error(`Error listening to impressions for ${ad.id}:`, err);
      });

      const unsubView = onSnapshot(qView, (snap) => {
        setStats(prev => ({
          ...prev,
          [ad.id]: {
            ...prev[ad.id],
            views: snap.size
          }
        }));
      }, (err) => {
        console.error(`Error listening to views for ${ad.id}:`, err);
      });

      const unsubClick = onSnapshot(qClick, (snap) => {
        setStats(prev => ({
          ...prev,
          [ad.id]: {
            ...prev[ad.id],
            clicks: snap.size
          }
        }));
      }, (err) => {
        console.error(`Error listening to clicks for ${ad.id}:`, err);
      });

      unsubs.push(unsubImp, unsubView, unsubClick);
    });

    return () => {
      unsubs.forEach(unsub => unsub());
    };
  }, [ads]);

  const openAddModal = () => {
    setEditingAd(null);
    setTitle('');
    setDescription('');
    setVideoUrl('');
    setThumbnail('');
    setAdvertiserName('');
    setStartDate(new Date().toISOString().slice(0, 10));
    setEndDate(new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10));
    setBudget(10000000);
    setPriority(3);
    setStatus('active');
    setCtaText('Tìm hiểu thêm');
    setTargetUrl('');
    setIsModalOpen(true);
  };

  const openEditModal = (ad: Ad) => {
    setEditingAd(ad);
    setTitle(ad.title);
    setDescription(ad.description);
    setVideoUrl(ad.videoUrl);
    setThumbnail(ad.thumbnail);
    setAdvertiserName(ad.advertiserName);
    setStartDate(new Date(ad.startDate).toISOString().slice(0, 10));
    setEndDate(new Date(ad.endDate).toISOString().slice(0, 10));
    setBudget(ad.budget);
    setPriority(ad.priority);
    setStatus(ad.status);
    setCtaText(ad.ctaText);
    setTargetUrl(ad.targetUrl);
    setIsModalOpen(true);
  };

  const handleDelete = async (adId: string) => {
    if (!window.confirm("Bạn có chắc chắn muốn xóa quảng cáo này? Dữ liệu thống kê vẫn sẽ được lưu trữ.")) return;
    try {
      await deleteDoc(doc(db, 'ads', adId));
    } catch (err) {
      console.error("Error deleting ad:", err);
      alert("Lỗi khi xóa quảng cáo!");
    }
  };

  const handleToggleStatus = async (ad: Ad) => {
    const newStatus = ad.status === 'active' ? 'paused' : 'active';
    try {
      await updateDoc(doc(db, 'ads', ad.id), { status: newStatus });
    } catch (err) {
      console.error("Error toggling status:", err);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!title || !videoUrl || !targetUrl || !advertiserName) {
      alert("Vui lòng điền đầy đủ các trường thông tin bắt buộc!");
      return;
    }

    const adData = {
      title,
      description,
      videoUrl,
      thumbnail: thumbnail || 'https://picsum.photos/200/300',
      advertiserName,
      advertiserId: editingAd?.advertiserId || 'admin',
      startDate: new Date(startDate).getTime(),
      endDate: new Date(endDate).getTime(),
      budget: Number(budget),
      priority: Number(priority),
      status,
      ctaText,
      targetUrl,
    };

    try {
      if (editingAd) {
        await updateDoc(doc(db, 'ads', editingAd.id), adData);
      } else {
        await addDoc(collection(db, 'ads'), adData);
      }
      setIsModalOpen(false);
    } catch (err) {
      console.error("Error saving ad:", err);
      alert("Có lỗi xảy ra khi lưu quảng cáo!");
    }
  };

  // Aggregate stats across all ads
  const statsList = Object.values(stats) as { impressions: number; views: number; clicks: number }[];
  const totalImpressions = statsList.reduce((sum, s) => sum + s.impressions, 0);
  const totalViews = statsList.reduce((sum, s) => sum + s.views, 0);
  const totalClicks = statsList.reduce((sum, s) => sum + s.clicks, 0);
  const totalCtr = totalImpressions > 0 ? (totalClicks / totalImpressions) * 100 : 0;
  
  // Total cost (approximate budget usage based on 500đ / impression)
  const totalSpent = totalImpressions * 500;

  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div className="flex flex-col md:flex-row md:items-end justify-between gap-4">
        <div>
          <h2 className="font-headline text-3xl font-bold text-on-surface mb-2">Quản lý Quảng cáo</h2>
          <p className="text-on-surface-variant font-body text-base">Tạo mới, chỉnh sửa, giám sát hiển thị và tối ưu hóa phân phối quảng cáo ngắn.</p>
        </div>
        <div className="flex items-center gap-3">
          <button 
            onClick={() => setShowCloudinaryConfig(!showCloudinaryConfig)}
            className="flex items-center gap-2 px-4 py-2 border border-outline-variant rounded-lg font-label text-sm text-on-surface hover:bg-surface-high transition-colors"
          >
            <Megaphone className="w-4 h-4 text-secondary" />
            Cấu hình Cloudinary
          </button>
          {authUser?.role !== 'viewer' && (
            <button 
              onClick={openAddModal}
              className="flex items-center gap-2 px-4 py-2 bg-primary text-on-primary rounded-lg font-label text-sm hover:bg-primary/90 transition-colors shadow-md"
            >
              <Plus className="w-4 h-4" />
              Tạo Quảng cáo
            </button>
          )}
        </div>
      </div>

      {/* Cloudinary Config Card */}
      {showCloudinaryConfig && (
        <div className="bg-surface-low border border-outline-variant/20 rounded-xl p-6 relative shadow-md animate-fade-in">
          <div className="absolute top-0 left-0 w-full h-[1px] bg-gradient-to-r from-transparent via-secondary/50 to-transparent"></div>
          <h3 className="font-headline text-lg font-bold text-on-surface mb-2 flex items-center gap-2">
            ☁️ Cấu hình Tải lên Cloudinary (Unsigned Preset)
          </h3>
          <p className="font-body text-sm text-on-surface-variant mb-4">
            Thiết lập Cloud Name và Upload Preset của Cloudinary để tải trực tiếp video/ảnh lên đám mây. Bạn cũng có thể thiết lập các biến này trong file <code className="text-primary font-mono font-bold">.env</code> làm mặc định.
          </p>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
            <div className="space-y-2">
              <label className="font-label text-xs text-on-surface-variant font-semibold">Cloud Name</label>
              <input
                type="text"
                value={cloudName}
                onChange={(e) => setCloudName(e.target.value)}
                placeholder="Nhập Cloud Name..."
                className="w-full bg-surface border border-outline-variant/30 text-on-surface rounded-lg px-4 py-2 outline-none focus:border-secondary transition-all font-body text-sm"
              />
            </div>
            <div className="space-y-2">
              <label className="font-label text-xs text-on-surface-variant font-semibold">Upload Preset (Unsigned)</label>
              <input
                type="text"
                value={uploadPreset}
                onChange={(e) => setUploadPreset(e.target.value)}
                placeholder="Nhập Upload Preset..."
                className="w-full bg-surface border border-outline-variant/30 text-on-surface rounded-lg px-4 py-2 outline-none focus:border-secondary transition-all font-body text-sm"
              />
            </div>
          </div>
          <div className="flex justify-end gap-2">
            <button
              onClick={() => setShowCloudinaryConfig(false)}
              className="px-4 py-1.5 border border-outline-variant/30 text-on-surface rounded-lg font-label text-xs hover:bg-surface-high transition-colors"
            >
              Hủy
            </button>
            <button
              onClick={handleSaveConfig}
              className="px-4 py-1.5 bg-secondary text-on-surface rounded-lg font-label text-xs hover:bg-secondary/90 font-bold transition-colors shadow-sm"
            >
              Lưu cấu hình
            </button>
          </div>
        </div>
      )}

      {/* Ad Statistics Panel */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="glass-panel rounded-xl p-6 flex items-center justify-between">
          <div>
            <h3 className="font-label text-xs text-on-surface-variant uppercase tracking-wider">Tổng Lượt hiển thị</h3>
            <span className="font-headline text-3xl font-bold text-on-surface mt-2 block">{loading ? '...' : totalImpressions.toLocaleString()}</span>
          </div>
          <div className="p-3 bg-primary/10 rounded-lg text-primary">
            <TrendingUp className="w-6 h-6" />
          </div>
        </div>

        <div className="glass-panel rounded-xl p-6 flex items-center justify-between">
          <div>
            <h3 className="font-label text-xs text-on-surface-variant uppercase tracking-wider">Lượt Xem ( $\ge 2s$)</h3>
            <span className="font-headline text-3xl font-bold text-on-surface mt-2 block">{loading ? '...' : totalViews.toLocaleString()}</span>
          </div>
          <div className="p-3 bg-secondary/10 rounded-lg text-secondary">
            <Eye className="w-6 h-6" />
          </div>
        </div>

        <div className="glass-panel rounded-xl p-6 flex items-center justify-between">
          <div>
            <h3 className="font-label text-xs text-on-surface-variant uppercase tracking-wider">Số Lượt Nhấp (Click)</h3>
            <span className="font-headline text-3xl font-bold text-on-surface mt-2 block">{loading ? '...' : totalClicks.toLocaleString()}</span>
          </div>
          <div className="p-3 bg-tertiary/10 rounded-lg text-tertiary">
            <Megaphone className="w-6 h-6" />
          </div>
        </div>

        <div className="glass-panel rounded-xl p-6 flex items-center justify-between">
          <div>
            <h3 className="font-label text-xs text-on-surface-variant uppercase tracking-wider">Tỷ lệ CTR Trung bình</h3>
            <span className="font-headline text-3xl font-bold text-primary mt-2 block">{loading ? '...' : `${totalCtr.toFixed(2)}%`}</span>
          </div>
          <div className="p-3 bg-primary/10 rounded-lg text-primary">
            <Percent className="w-6 h-6" />
          </div>
        </div>
      </div>

      {/* Ads Table */}
      <div className="bg-surface-low border border-outline-variant/20 rounded-xl overflow-hidden relative shadow-sm">
        <div className="absolute top-0 left-0 w-full h-[1px] bg-gradient-to-r from-transparent via-primary/50 to-transparent"></div>
        
        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse min-w-[950px]">
            <thead>
              <tr className="border-b border-outline-variant/10 bg-surface/50">
                <th className="py-3 px-6 font-label text-xs text-on-surface-variant uppercase tracking-wider font-semibold">Chiến dịch</th>
                <th className="py-3 px-6 font-label text-xs text-on-surface-variant uppercase tracking-wider font-semibold">Nhà quảng cáo</th>
                <th className="py-3 px-6 font-label text-xs text-on-surface-variant uppercase tracking-wider font-semibold">Trạng thái</th>
                <th className="py-3 px-6 font-label text-xs text-on-surface-variant uppercase tracking-wider font-semibold">Ngân sách</th>
                <th className="py-3 px-6 font-label text-xs text-on-surface-variant uppercase tracking-wider font-semibold">Hiệu suất (Imp / View / Click)</th>
                <th className="py-3 px-6 font-label text-xs text-on-surface-variant uppercase tracking-wider font-semibold">CTR / CPC</th>
                <th className="py-3 px-6 font-label text-xs text-on-surface-variant uppercase tracking-wider font-semibold text-right">Thao tác</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-outline-variant/10">
              {loading ? (
                <tr>
                  <td colSpan={7} className="py-8 text-center text-on-surface-variant">
                    <RefreshCw className="w-5 h-5 animate-spin inline-block mr-2" />
                    Đang tải danh sách quảng cáo...
                  </td>
                </tr>
              ) : ads.length === 0 ? (
                <tr>
                  <td colSpan={7} className="py-8 text-center text-on-surface-variant">Không có quảng cáo nào được cấu hình.</td>
                </tr>
              ) : ads.map((ad) => {
                const adMetrics = stats[ad.id] || { impressions: 0, views: 0, clicks: 0 };
                const adCtr = adMetrics.impressions > 0 ? (adMetrics.clicks / adMetrics.impressions) * 100 : 0;
                
                // CPC = spent / clicks
                const spent = adMetrics.impressions * 500;
                const adCpc = adMetrics.clicks > 0 ? spent / adMetrics.clicks : 0;

                return (
                  <tr key={ad.id} className="hover:bg-surface-high/30 transition-colors group">
                    <td className="py-4 px-6">
                      <div className="font-medium text-on-surface">{ad.title}</div>
                      <div className="font-label text-xs text-on-surface-variant mt-0.5 max-w-[280px] truncate">{ad.description}</div>
                    </td>
                    <td className="py-4 px-6">
                      <div className="text-sm text-on-surface font-semibold">@{ad.advertiserName}</div>
                      <div className="text-xs text-on-surface-variant font-mono">{ad.id}</div>
                    </td>
                    <td className="py-4 px-6">
                      <span className={`status-badge ${
                        ad.status === 'active' ? 'badge-resolved' :
                        ad.status === 'paused' ? 'badge-reviewing' :
                        ad.status === 'expired' ? 'badge-dismissed' :
                        'badge-pending'
                      }`}>
                        <span className={`w-1.5 h-1.5 rounded-full bg-current ${ad.status === 'active' ? 'animate-pulse' : ''}`}></span>
                        {ad.status === 'active' ? 'Đang chạy' : ad.status === 'paused' ? 'Tạm dừng' : ad.status === 'expired' ? 'Hết hạn' : 'Chờ duyệt'}
                      </span>
                    </td>
                    <td className="py-4 px-6 text-sm text-on-surface font-medium">
                      {ad.budget.toLocaleString('vi-VN')} đ
                    </td>
                    <td className="py-4 px-6">
                      <div className="text-sm text-on-surface">{adMetrics.impressions.toLocaleString()} imp</div>
                      <div className="text-xs text-on-surface-variant">{adMetrics.views.toLocaleString()} views / {adMetrics.clicks.toLocaleString()} clicks</div>
                    </td>
                    <td className="py-4 px-6">
                      <div className="text-sm text-primary font-bold">{adCtr.toFixed(2)}% CTR</div>
                      <div className="text-xs text-on-surface-variant">{adCpc > 0 ? `${Math.round(adCpc).toLocaleString()}đ CPC` : '0đ CPC'}</div>
                    </td>
                    <td className="py-4 px-6 text-right">
                      <div className="flex items-center justify-end gap-2 opacity-0 group-hover:opacity-100 transition-opacity">
                        <button
                          onClick={() => handleToggleStatus(ad)}
                          className={`p-1.5 rounded transition-colors ${
                            ad.status === 'active' 
                              ? 'text-on-surface-variant hover:text-tertiary hover:bg-tertiary/10' 
                              : 'text-on-surface-variant hover:text-secondary hover:bg-secondary/10'
                          }`}
                          title={ad.status === 'active' ? "Tạm dừng" : "Bắt đầu chạy"}
                        >
                          {ad.status === 'active' ? <Pause className="w-5 h-5" /> : <Play className="w-5 h-5" />}
                        </button>
                        
                        <button
                          onClick={() => openEditModal(ad)}
                          className="p-1.5 text-on-surface-variant hover:text-primary hover:bg-primary/10 rounded transition-colors"
                          title="Sửa quảng cáo"
                        >
                          <Edit2 className="w-5 h-5" />
                        </button>

                        <button
                          onClick={() => handleDelete(ad.id)}
                          className="p-1.5 text-on-surface-variant hover:text-error hover:bg-error/10 rounded transition-colors"
                          title="Xóa quảng cáo"
                        >
                          <Trash2 className="w-5 h-5" />
                        </button>
                      </div>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>

      {/* Create / Edit Ad Modal */}
      {isModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 overflow-y-auto">
          <div className="bg-surface-low border border-outline-variant/30 rounded-2xl w-full max-w-2xl max-h-[90vh] flex flex-col shadow-2xl relative overflow-hidden">
            <div className="absolute top-0 left-0 w-full h-[2px] bg-primary"></div>
            
            {/* Modal Header */}
            <div className="p-6 border-b border-outline-variant/10 flex justify-between items-center bg-surface/50">
              <h3 className="font-headline text-xl font-bold text-on-surface flex items-center gap-2">
                <Megaphone className="w-5 h-5 text-primary" />
                {editingAd ? "Cập nhật chiến dịch Quảng cáo" : "Tạo chiến dịch Quảng cáo mới"}
              </h3>
              <button 
                onClick={() => setIsModalOpen(false)}
                className="text-on-surface-variant hover:text-on-surface p-1 rounded-full hover:bg-surface-high transition-all"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            {/* Modal Form Body */}
            <form onSubmit={handleSubmit} className="flex-1 p-6 space-y-4 overflow-y-auto">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div className="space-y-2">
                  <label className="font-label text-sm text-on-surface-variant">Tên chiến dịch *</label>
                  <input
                    type="text"
                    required
                    value={title}
                    onChange={(e) => setTitle(e.target.value)}
                    placeholder="Nhập tên chiến dịch..."
                    className="w-full bg-surface border border-outline-variant/30 text-on-surface rounded-lg px-4 py-2 outline-none focus:border-primary transition-all font-body"
                  />
                </div>
                <div className="space-y-2">
                  <label className="font-label text-sm text-on-surface-variant">Nhà tài trợ (@username) *</label>
                  <input
                    type="text"
                    required
                    value={advertiserName}
                    onChange={(e) => setAdvertiserName(e.target.value)}
                    placeholder="Tên nhà quảng cáo..."
                    className="w-full bg-surface border border-outline-variant/30 text-on-surface rounded-lg px-4 py-2 outline-none focus:border-primary transition-all font-body"
                  />
                </div>
              </div>

              <div className="space-y-2">
                <label className="font-label text-sm text-on-surface-variant">Mô tả chiến dịch</label>
                <textarea
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                  placeholder="Nội dung mô tả hoặc Hashtags chiến dịch..."
                  rows={3}
                  className="w-full bg-surface border border-outline-variant/30 text-on-surface rounded-lg px-4 py-2 outline-none focus:border-primary transition-all font-body resize-none"
                />
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                {/* Video Upload & URL */}
                <div className="space-y-2 border border-outline-variant/10 p-4 rounded-xl bg-surface-lowest/40">
                  <label className="font-label text-sm text-on-surface-variant font-semibold block">Nội dung Video *</label>
                  
                  {/* File selector button */}
                  <div className="flex items-center gap-3">
                    <label className={clsx(
                      "flex items-center justify-center gap-2 px-4 py-2 rounded-lg font-label text-sm border cursor-pointer transition-all shadow-sm select-none",
                      uploadingVideo 
                        ? "bg-surface-high border-outline-variant text-on-surface-variant cursor-not-allowed" 
                        : "bg-surface border-outline-variant hover:bg-surface-high text-on-surface hover:text-primary"
                    )}>
                      <RefreshCw className={clsx("w-4 h-4", uploadingVideo && "animate-spin")} />
                      {uploadingVideo ? `Đang tải lên ${videoProgress}%` : "Chọn file Video (.mp4)"}
                      <input
                        type="file"
                        accept="video/mp4,video/*"
                        disabled={uploadingVideo}
                        onChange={(e) => {
                          const file = e.target.files?.[0];
                          if (file) handleUploadFile(file, 'video');
                        }}
                        className="hidden"
                      />
                    </label>
                    {videoUrl && <span className="text-xs text-secondary font-label font-semibold">✓ Đã tải lên</span>}
                  </div>

                  {/* Progress bar */}
                  {uploadingVideo && (
                    <div className="w-full bg-surface-high h-1.5 rounded-full overflow-hidden">
                      <div className="bg-primary h-full transition-all duration-300" style={{ width: `${videoProgress}%` }}></div>
                    </div>
                  )}

                  {/* URL Input */}
                  <input
                    type="url"
                    required
                    value={videoUrl}
                    onChange={(e) => setVideoUrl(e.target.value)}
                    placeholder="Đường dẫn video (.mp4)..."
                    className="w-full bg-surface border border-outline-variant/30 text-on-surface rounded-lg px-3 py-1.5 outline-none focus:border-primary transition-all font-mono text-xs mt-2"
                  />
                </div>

                {/* Thumbnail Upload & URL */}
                <div className="space-y-2 border border-outline-variant/10 p-4 rounded-xl bg-surface-lowest/40">
                  <label className="font-label text-sm text-on-surface-variant font-semibold block">Ảnh bìa (Thumbnail)</label>
                  
                  {/* File selector button */}
                  <div className="flex items-center gap-3">
                    <label className={clsx(
                      "flex items-center justify-center gap-2 px-4 py-2 rounded-lg font-label text-sm border cursor-pointer transition-all shadow-sm select-none",
                      uploadingThumb 
                        ? "bg-surface-high border-outline-variant text-on-surface-variant cursor-not-allowed" 
                        : "bg-surface border-outline-variant hover:bg-surface-high text-on-surface hover:text-secondary"
                    )}>
                      <RefreshCw className={clsx("w-4 h-4", uploadingThumb && "animate-spin")} />
                      {uploadingThumb ? `Đang tải lên ${thumbProgress}%` : "Chọn ảnh bìa (.jpg/.png)"}
                      <input
                        type="file"
                        accept="image/*"
                        disabled={uploadingThumb}
                        onChange={(e) => {
                          const file = e.target.files?.[0];
                          if (file) handleUploadFile(file, 'image');
                        }}
                        className="hidden"
                      />
                    </label>
                    {thumbnail && <span className="text-xs text-secondary font-label font-semibold">✓ Đã tải lên</span>}
                  </div>

                  {/* Progress bar */}
                  {uploadingThumb && (
                    <div className="w-full bg-surface-high h-1.5 rounded-full overflow-hidden">
                      <div className="bg-secondary h-full transition-all duration-300" style={{ width: `${thumbProgress}%` }}></div>
                    </div>
                  )}

                  {/* URL Input */}
                  <input
                    type="url"
                    value={thumbnail}
                    onChange={(e) => setThumbnail(e.target.value)}
                    placeholder="Đường dẫn ảnh bìa..."
                    className="w-full bg-surface border border-outline-variant/30 text-on-surface rounded-lg px-3 py-1.5 outline-none focus:border-primary transition-all font-mono text-xs mt-2"
                  />
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div className="space-y-2">
                  <label className="font-label text-sm text-on-surface-variant">Trang đích (Landing Page URL) *</label>
                  <input
                    type="url"
                    required
                    value={targetUrl}
                    onChange={(e) => setTargetUrl(e.target.value)}
                    placeholder="https://shopee.vn/my-shop"
                    className="w-full bg-surface border border-outline-variant/30 text-on-surface rounded-lg px-4 py-2 outline-none focus:border-primary transition-all font-mono text-sm"
                  />
                </div>
                <div className="space-y-2">
                  <label className="font-label text-sm text-on-surface-variant">Kêu gọi hành động (CTA Text)</label>
                  <select
                    value={ctaText}
                    onChange={(e) => setCtaText(e.target.value)}
                    className="w-full bg-surface border border-outline-variant/30 text-on-surface rounded-lg px-4 py-2 outline-none focus:border-primary transition-all font-label text-sm"
                  >
                    <option value="Tìm hiểu thêm">Tìm hiểu thêm</option>
                    <option value="Đặt ngay">Đặt ngay</option>
                    <option value="Mua ngay">Mua ngay</option>
                    <option value="Tải ngay">Tải ngay</option>
                    <option value="Đăng ký">Đăng ký</option>
                    <option value="Mở link">Mở link</option>
                  </select>
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div className="space-y-2">
                  <label className="font-label text-sm text-on-surface-variant">Ngân sách (VND)</label>
                  <input
                    type="number"
                    value={budget}
                    onChange={(e) => setBudget(Number(e.target.value))}
                    className="w-full bg-surface border border-outline-variant/30 text-on-surface rounded-lg px-4 py-2 outline-none focus:border-primary transition-all font-body"
                  />
                </div>
                <div className="space-y-2">
                  <label className="font-label text-sm text-on-surface-variant">Độ ưu tiên (Priority 1-5)</label>
                  <input
                    type="number"
                    min={1}
                    max={5}
                    value={priority}
                    onChange={(e) => setPriority(Number(e.target.value))}
                    className="w-full bg-surface border border-outline-variant/30 text-on-surface rounded-lg px-4 py-2 outline-none focus:border-primary transition-all font-body"
                  />
                </div>
                <div className="space-y-2">
                  <label className="font-label text-sm text-on-surface-variant">Trạng thái khởi tạo</label>
                  <select
                    value={status}
                    onChange={(e) => setStatus(e.target.value as AdStatus)}
                    className="w-full bg-surface border border-outline-variant/30 text-on-surface rounded-lg px-4 py-2 outline-none focus:border-primary transition-all font-label text-sm"
                  >
                    <option value="active">Kích hoạt ngay (Active)</option>
                    <option value="paused">Tạm dừng (Paused)</option>
                    <option value="expired">Hết hạn (Expired)</option>
                    <option value="pending">Chờ duyệt (Pending)</option>
                  </select>
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div className="space-y-2">
                  <label className="font-label text-sm text-on-surface-variant">Ngày bắt đầu</label>
                  <input
                    type="date"
                    value={startDate}
                    onChange={(e) => setStartDate(e.target.value)}
                    className="w-full bg-surface border border-outline-variant/30 text-on-surface rounded-lg px-4 py-2 outline-none focus:border-primary transition-all font-body"
                  />
                </div>
                <div className="space-y-2">
                  <label className="font-label text-sm text-on-surface-variant">Ngày kết thúc</label>
                  <input
                    type="date"
                    value={endDate}
                    onChange={(e) => setEndDate(e.target.value)}
                    className="w-full bg-surface border border-outline-variant/30 text-on-surface rounded-lg px-4 py-2 outline-none focus:border-primary transition-all font-body"
                  />
                </div>
              </div>

              {/* Modal Actions */}
              <div className="pt-6 border-t border-outline-variant/10 flex justify-end gap-3 bg-surface/30">
                <button
                  type="button"
                  onClick={() => setIsModalOpen(false)}
                  className="px-4 py-2 border border-outline-variant/30 text-on-surface rounded-lg font-label text-sm hover:bg-surface-high transition-colors"
                >
                  Hủy bỏ
                </button>
                <button
                  type="submit"
                  className="px-6 py-2 bg-primary text-on-primary rounded-lg font-label text-sm hover:bg-primary/90 transition-colors shadow-md"
                >
                  {editingAd ? "Lưu thay đổi" : "Tạo mới"}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
