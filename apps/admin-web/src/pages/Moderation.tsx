import { useState, useEffect, useRef, useCallback } from 'react';
import { useAuth } from '../components/auth-provider';
import { Play, AlertTriangle, Flag, Trash2, Check, RefreshCw, X, BrainCircuit, Loader2, Sparkles, ShieldAlert, CheckCircle2, XCircle, Clock } from 'lucide-react';
import { clsx } from 'clsx';
import { db, collection, onSnapshot, doc, updateDoc, addDoc, Timestamp } from '../lib/firebase';
import { moderateVideoContent } from '../lib/gemini';
import { formatTimeAgo } from '../lib/utils';
import type { Video } from '../types';
import type { AIModerationResult } from '../lib/gemini';

type TabFilter = 'pending' | 'approved' | 'rejected';

export function Moderation() {
  const { user } = useAuth();
  const adminName = user?.email || 'admin_unknown';

  const [videos, setVideos] = useState<Video[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<TabFilter>('pending');
  const [rejectingId, setRejectingId] = useState<string | null>(null);
  const [rejectReason, setRejectReason] = useState('');
  const [playingVideo, setPlayingVideo] = useState<Video | null>(null);

  // AI states
  const [scanningId, setScanningId] = useState<string | null>(null);
  const [scanningAll, setScanningAll] = useState(false);
  const [aiResults, setAiResults] = useState<Map<string, AIModerationResult>>(new Map());
  const autoScanningIdsRef = useRef<Set<string>>(new Set());

  // Shared AI moderation helper — eliminates triplicate code
  const moderateAndUpdate = useCallback(async (video: Video): Promise<AIModerationResult | null> => {
    try {
      const result = await moderateVideoContent(video.description, video.username);
      setAiResults((prev) => new Map(prev).set(video.videoId, result));

      const updatePayload: Record<string, unknown> = {
        aiFlagged: result.isViolation,
        aiConfidence: result.confidence,
        aiReviewed: true,
      };

      if (!result.isViolation) {
        updatePayload.moderationStatus = 'approved';
        updatePayload.reviewedBy = 'AI_AUTO';
      }

      await updateDoc(doc(db, 'videos', video.videoId), updatePayload);

      if (!result.isViolation) {
        await addDoc(collection(db, 'audit_logs'), {
          adminId: 'AI_AUTO',
          action: 'AUTO_APPROVE_VIDEO',
          targetId: video.videoId,
          details: {
            confidence: result.confidence,
            reason: result.reason || 'AI đánh giá nội dung an toàn',
          },
          createdAt: Timestamp.now(),
        });
      }
      return result;
    } catch (err) {
      console.error('AI moderation error for', video.videoId, err);
      return null;
    }
  }, []);

  useEffect(() => {
    const unsubscribe = onSnapshot(collection(db, 'videos'), (snapshot) => {
      const videosData: Video[] = [];
      snapshot.forEach((docSnap) => {
        const data = docSnap.data();
        videosData.push({
          videoId: docSnap.id,
          videoUri: data.videoUri || '',
          authorId: data.authorId || '',
          username: data.username || 'Ẩn danh',
          description: data.description || '',
          timestamp: data.timestamp || 0,
          totalLikes: data.totalLikes || 0,
          totalComments: data.totalComments || 0,
          watchCount: data.watchCount || 0,
          moderationStatus: data.moderationStatus || 'approved',
          aiFlagged: data.aiFlagged || false,
          aiConfidence: data.aiConfidence || 0,
          aiReviewed: data.aiReviewed || false,
          rejectedReason: data.rejectedReason || '',
          reviewedBy: data.reviewedBy || '',
        });
      });
      videosData.sort((a, b) => b.timestamp - a.timestamp);
      setVideos(videosData);
      setLoading(false);
    });

    return () => unsubscribe();
  }, []);

  // Auto-scan pending unreviewed videos (uses ref to avoid infinite loop)
  useEffect(() => {
    const pendingUnreviewedVideos = videos.filter(
      (video) => video.moderationStatus === 'pending' && !video.aiReviewed && !autoScanningIdsRef.current.has(video.videoId),
    );

    if (pendingUnreviewedVideos.length === 0) return;

    // Mark as scanning in ref (not state) to avoid re-trigger
    pendingUnreviewedVideos.forEach((video) => autoScanningIdsRef.current.add(video.videoId));

    const runAutoModeration = async () => {
      for (const video of pendingUnreviewedVideos) {
        await moderateAndUpdate(video);
        autoScanningIdsRef.current.delete(video.videoId);
      }
    };

    void runAutoModeration();
  }, [videos, moderateAndUpdate]);

  const handleApprove = async (videoId: string) => {
    try {
      await updateDoc(doc(db, 'videos', videoId), {
        moderationStatus: 'approved',
        reviewedBy: adminName,
      });
      await addDoc(collection(db, 'audit_logs'), {
        adminId: adminName,
        action: 'APPROVE_VIDEO',
        targetId: videoId,
        details: {},
        createdAt: Timestamp.now(),
      });
    } catch (err) {
      console.error('Error approving video:', err);
      alert('Lỗi khi duyệt video!');
    }
  };

  const handleReject = async (videoId: string, reason?: string) => {
    try {
      const finalReason = reason || rejectReason || 'Vi phạm tiêu chuẩn cộng đồng';
      await updateDoc(doc(db, 'videos', videoId), {
        moderationStatus: 'rejected',
        rejectedReason: finalReason,
        reviewedBy: adminName,
      });
      await addDoc(collection(db, 'audit_logs'), {
        adminId: adminName,
        action: 'REJECT_VIDEO',
        targetId: videoId,
        details: { reason: finalReason },
        createdAt: Timestamp.now(),
      });
      setRejectingId(null);
      setRejectReason('');
    } catch (err) {
      console.error('Error rejecting video:', err);
      alert('Lỗi khi từ chối video!');
    }
  };

  // --- AI Moderation ---
  const handleAIScan = async (video: Video) => {
    setScanningId(video.videoId);
    await moderateAndUpdate(video);
    setScanningId(null);
  };

  const handleAIScanAll = async () => {
    const pendingVideos = videos.filter((v) => v.moderationStatus === 'pending');
    if (pendingVideos.length === 0) return;

    setScanningAll(true);
    for (const video of pendingVideos) {
      await moderateAndUpdate(video);
      // Delay to avoid rate limiting
      await new Promise((r) => setTimeout(r, 800));
    }
    setScanningAll(false);
  };

  const normStatus = (s?: string) => (s || 'pending').trim().toLowerCase();
  const filteredVideos = videos.filter((v) => normStatus(v.moderationStatus) === activeTab);
  const pendingCount = videos.filter((v) => normStatus(v.moderationStatus) === 'pending').length;
  const approvedCount = videos.filter((v) => normStatus(v.moderationStatus) === 'approved').length;
  const rejectedCount = videos.filter((v) => normStatus(v.moderationStatus) === 'rejected').length;



  return (
    <div className="space-y-6">
      {/* Page Header & Tabs */}
      <div className="flex flex-col md:flex-row md:items-end justify-between gap-4">
        <div>
          <h2 className="font-headline text-3xl font-bold text-on-surface mb-2">Kiểm duyệt Video</h2>
          <p className="font-body text-base text-on-surface-variant max-w-2xl">
            Quản lý và duyệt video. Tích hợp <strong className="text-primary">Gemini AI</strong> kiểm duyệt tự động.
          </p>
        </div>
        <div className="flex items-center gap-3">
          {/* AI Scan All Button */}
          {activeTab === 'pending' && pendingCount > 0 && (
            <button
              onClick={handleAIScanAll}
              disabled={scanningAll}
              className="flex items-center gap-2 px-4 py-2 bg-gradient-to-r from-primary/90 to-secondary/90 text-on-primary rounded-lg font-label text-sm font-bold shadow-lg shadow-primary/20 hover:shadow-xl transition-all disabled:opacity-50"
            >
              {scanningAll ? (
                <Loader2 className="w-4 h-4 animate-spin" />
              ) : (
                <BrainCircuit className="w-4 h-4" />
              )}
              {scanningAll ? `Đang quét...` : `AI Quét tất cả (${pendingCount})`}
            </button>
          )}

          <div className="flex bg-surface-low rounded-lg p-1 border border-outline-variant/20 inline-flex">
            <button
              onClick={() => setActiveTab('pending')}
              className={clsx("px-4 py-2 rounded-md font-label text-sm transition-all", activeTab === 'pending' ? "bg-surface-highest text-on-surface shadow-sm font-bold" : "text-on-surface-variant hover:text-on-surface hover:bg-surface-high")}
            >
              Chờ duyệt ({pendingCount})
            </button>
            <button
              onClick={() => setActiveTab('approved')}
              className={clsx("px-4 py-2 rounded-md font-label text-sm transition-all", activeTab === 'approved' ? "bg-surface-highest text-on-surface shadow-sm font-bold" : "text-on-surface-variant hover:text-on-surface hover:bg-surface-high")}
            >
              Đã duyệt ({approvedCount})
            </button>
            <button
              onClick={() => setActiveTab('rejected')}
              className={clsx("px-4 py-2 rounded-md font-label text-sm transition-all", activeTab === 'rejected' ? "bg-surface-highest text-on-surface shadow-sm font-bold" : "text-on-surface-variant hover:text-on-surface hover:bg-surface-high")}
            >
              Đã gỡ bỏ ({rejectedCount})
            </button>
          </div>
        </div>
      </div>

      {/* Loading / Empty */}
      {loading ? (
        <div className="flex items-center justify-center py-20">
          <RefreshCw className="w-8 h-8 animate-spin text-primary" />
          <span className="ml-3 text-on-surface-variant font-label">Đang tải video từ Firestore...</span>
        </div>
      ) : filteredVideos.length === 0 ? (
        <div className="text-center py-20 text-on-surface-variant">
          <p className="text-lg font-headline mb-2">Không có video nào</p>
          <p className="font-label text-sm">
            {activeTab === 'pending' ? 'Tất cả video đã được xử lý.' :
              activeTab === 'approved' ? 'Chưa có video nào được duyệt.' :
                'Chưa có video nào bị từ chối.'}
          </p>
        </div>
      ) : (
        /* Video Grid */
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
          {filteredVideos.map((video) => {
            const aiResult = aiResults.get(video.videoId);
            const isScanning = scanningId === video.videoId;

            return (
              <div key={video.videoId} className={clsx(
                "glass-panel glass-panel-hover rounded-xl overflow-hidden flex flex-col transition-all duration-300",
                (video.aiFlagged || aiResult?.isViolation) && "border-error/30"
              )}>
                {/* Thumbnail / Video Preview */}
                <div
                  className="relative w-full aspect-[9/16] bg-surface-highest group cursor-pointer overflow-hidden"
                  onClick={() => setPlayingVideo(video)}
                >
                  {video.videoUri ? (
                    <video
                      src={video.videoUri}
                      className="w-full h-full object-cover opacity-80 group-hover:opacity-100 transition-all duration-300"
                      muted
                      preload="metadata"
                      onMouseEnter={(e) => {
                        const v = e.target as HTMLVideoElement;
                        v.play().catch(() => { });
                        // Auto-pause after 3 seconds to save resources
                        const timeoutId = setTimeout(() => { v.pause(); }, 3000);
                        (v as any)._hoverTimeout = timeoutId;
                      }}
                      onMouseLeave={(e) => {
                        const v = e.target as HTMLVideoElement;
                        if ((v as any)._hoverTimeout) {
                          clearTimeout((v as any)._hoverTimeout);
                          (v as any)._hoverTimeout = null;
                        }
                        v.pause();
                        v.currentTime = 0;
                      }}
                    />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center bg-surface-high">
                      <Play className="w-12 h-12 text-on-surface-variant/30" />
                    </div>
                  )}

                  {/* Play Overlay */}
                  <div className="absolute inset-0 flex items-center justify-center bg-background/20 opacity-0 group-hover:opacity-100 transition-opacity">
                    <div className="w-12 h-12 rounded-full bg-background/60 backdrop-blur flex items-center justify-center border border-on-surface/20">
                      <Play className="w-6 h-6 text-on-surface fill-current" />
                    </div>
                  </div>

                  {/* Badges */}
                  <div className="absolute top-3 left-3 right-3 flex justify-between items-start">
                    {video.aiFlagged || aiResult?.isViolation ? (
                      <div className="backdrop-blur px-2.5 py-1 rounded flex items-center gap-1 font-label text-xs border bg-rose-500/25 text-rose-600 dark:text-rose-400 border-rose-500/30 font-bold shadow-sm">
                        <AlertTriangle className="w-3.5 h-3.5 text-rose-500" />
                        AI: {aiResult?.confidence || video.aiConfidence}% Vi phạm
                      </div>
                    ) : aiResult && !aiResult.isViolation ? (
                      <div className="backdrop-blur px-2.5 py-1 rounded flex items-center gap-1 font-label text-xs border bg-emerald-500/25 text-emerald-600 dark:text-emerald-400 border-emerald-500/30 font-bold shadow-sm">
                        <Sparkles className="w-3.5 h-3.5 text-emerald-500" />
                        AI: An toàn
                      </div>
                    ) : (
                      <>
                        {activeTab === 'approved' ? (
                          <div className="backdrop-blur px-2.5 py-1 rounded flex items-center gap-1 font-label text-xs border bg-emerald-500/25 text-emerald-600 dark:text-emerald-400 border-emerald-500/30 font-bold shadow-sm">
                            <CheckCircle2 className="w-3.5 h-3.5 text-emerald-500" />
                            Đã duyệt
                          </div>
                        ) : activeTab === 'rejected' ? (
                          <div className="backdrop-blur px-2.5 py-1 rounded flex items-center gap-1 font-label text-xs border bg-rose-500/25 text-rose-600 dark:text-rose-400 border-rose-500/30 font-bold shadow-sm">
                            <XCircle className="w-3.5 h-3.5 text-rose-500" />
                            Đã gỡ bỏ
                          </div>
                        ) : (
                          <div className="backdrop-blur px-2.5 py-1 rounded flex items-center gap-1 font-label text-xs border bg-amber-500/25 text-amber-600 dark:text-amber-400 border-amber-500/30 font-bold shadow-sm">
                            <Clock className="w-3.5 h-3.5 text-amber-500" />
                            Chờ duyệt
                          </div>
                        )}
                      </>
                    )}
                    <div className="bg-surface/80 backdrop-blur text-on-surface px-2 py-0.5 rounded font-label text-[10px]">
                      ❤ {video.totalLikes} · 👁 {video.watchCount}
                    </div>
                  </div>

                  {/* Rejection badge */}
                  {video.moderationStatus === 'rejected' && (
                    <div className="absolute bottom-3 left-3 right-3">
                      <div className="bg-error/90 backdrop-blur text-on-error px-3 py-1.5 rounded font-label text-xs">
                        Lý do: {video.rejectedReason || 'Không rõ'}
                      </div>
                    </div>
                  )}
                </div>

                {/* Content */}
                <div className="p-4 flex-1 flex flex-col bg-surface-low/50">
                  <div className="flex items-center gap-3 mb-3">
                    <div className="w-8 h-8 rounded-full bg-primary/20 flex items-center justify-center text-primary font-bold text-sm shrink-0">
                      {video.username.charAt(0).toUpperCase()}
                    </div>
                    <div className="min-w-0">
                      <p className="font-label text-sm text-on-surface truncate">@{video.username}</p>
                      <p className="text-[10px] text-on-surface-variant truncate">{formatTimeAgo(video.timestamp)}</p>
                    </div>
                  </div>
                  <p className="font-body text-sm text-on-surface-variant line-clamp-2 mb-3 flex-1">
                    {video.description || 'Không có mô tả'}
                  </p>

                  {/* AI Result Card */}
                  {aiResult && (
                    <div className={clsx(
                      "p-3 rounded-lg mb-3 border text-xs font-label shadow-sm transition-all duration-300",
                      aiResult.isViolation
                        ? "bg-rose-500/10 border-rose-500/30 text-rose-600 dark:text-rose-400"
                        : "bg-emerald-500/10 border-emerald-500/30 text-emerald-600 dark:text-emerald-400"
                    )}>
                      <div className="flex items-center gap-1.5 mb-1.5 font-bold text-sm">
                        {aiResult.isViolation ? <ShieldAlert className="w-4 h-4 text-rose-500" /> : <Sparkles className="w-4 h-4 text-emerald-500" />}
                        <span>{aiResult.isViolation ? `Vi phạm: ${aiResult.category}` : 'Nội dung an toàn'}</span>
                        <span className={clsx(
                          "ml-auto px-2 py-0.5 rounded text-[10px] font-extrabold",
                          aiResult.isViolation
                            ? "bg-rose-500/20 text-rose-700 dark:text-rose-300"
                            : "bg-emerald-500/20 text-emerald-700 dark:text-emerald-300"
                        )}>
                          {aiResult.confidence}%
                        </span>
                      </div>
                      <p className="line-clamp-2 mt-1 text-xs opacity-90 font-medium leading-relaxed">
                        {aiResult.reason}
                      </p>
                    </div>
                  )}

                  {/* Actions for PENDING */}
                  {activeTab === 'pending' && (
                    <div className="space-y-2 mt-auto">
                      {/* AI Scan button */}
                      <button
                        onClick={() => handleAIScan(video)}
                        disabled={isScanning || scanningAll}
                        className="w-full py-2 rounded border border-primary/30 text-primary hover:bg-primary/10 font-label text-sm flex items-center justify-center gap-1.5 transition-colors disabled:opacity-50"
                      >
                        {isScanning ? <Loader2 className="w-4 h-4 animate-spin" /> : <BrainCircuit className="w-4 h-4" />}
                        {isScanning ? 'Đang phân tích...' : 'AI Kiểm duyệt'}
                      </button>

                      {rejectingId === video.videoId ? (
                        <div className="space-y-2">
                          <input
                            type="text"
                            placeholder="Lý do từ chối..."
                            value={rejectReason}
                            onChange={(e) => setRejectReason(e.target.value)}
                            className="w-full bg-surface border border-outline-variant/20 text-on-surface font-label text-sm p-2 rounded outline-none focus:border-error"
                          />
                          <div className="grid grid-cols-2 gap-2">
                            <button
                              onClick={() => handleReject(video.videoId)}
                              className="py-2 rounded bg-error text-on-error hover:bg-error/90 font-label text-sm font-bold transition-colors"
                            >
                              Xác nhận gỡ
                            </button>
                            <button
                              onClick={() => { setRejectingId(null); setRejectReason(''); }}
                              className="py-2 rounded border border-outline-variant text-on-surface hover:bg-surface-high font-label text-sm transition-colors"
                            >
                              Hủy
                            </button>
                          </div>
                        </div>
                      ) : (
                        <div className="grid grid-cols-2 gap-2">
                          <button
                            onClick={() => setRejectingId(video.videoId)}
                            className="py-2 rounded border border-error text-error hover:bg-error/10 font-label text-sm flex items-center justify-center gap-1.5 transition-colors"
                          >
                            <Trash2 className="w-4 h-4" /> Gỡ bỏ
                          </button>
                          <button
                            onClick={() => handleApprove(video.videoId)}
                            className="py-2 rounded bg-secondary/20 text-secondary border border-secondary/30 hover:bg-secondary/30 font-label text-sm flex items-center justify-center gap-1.5 transition-colors"
                          >
                            <Check className="w-4 h-4" /> Duyệt
                          </button>
                        </div>
                      )}
                    </div>
                  )}

                  {/* Actions for APPROVED - can now REJECT */}
                  {activeTab === 'approved' && (
                    <div className="mt-auto space-y-2">
                      {rejectingId === video.videoId ? (
                        <div className="space-y-2">
                          <input
                            type="text"
                            placeholder="Lý do gỡ bỏ..."
                            value={rejectReason}
                            onChange={(e) => setRejectReason(e.target.value)}
                            className="w-full bg-surface border border-outline-variant/20 text-on-surface font-label text-sm p-2 rounded outline-none focus:border-error"
                          />
                          <div className="grid grid-cols-2 gap-2">
                            <button
                              onClick={() => handleReject(video.videoId)}
                              className="py-2 rounded bg-error text-on-error hover:bg-error/90 font-label text-sm font-bold transition-colors"
                            >
                              Xác nhận gỡ
                            </button>
                            <button
                              onClick={() => { setRejectingId(null); setRejectReason(''); }}
                              className="py-2 rounded border border-outline-variant text-on-surface hover:bg-surface-high font-label text-sm transition-colors"
                            >
                              Hủy
                            </button>
                          </div>
                        </div>
                      ) : (
                        <button
                          onClick={() => setRejectingId(video.videoId)}
                          className="w-full py-2 rounded border border-error/50 text-error hover:bg-error/10 font-label text-sm flex items-center justify-center gap-1.5 transition-colors"
                        >
                          <Trash2 className="w-4 h-4" /> Gỡ bỏ video
                        </button>
                      )}
                    </div>
                  )}

                  {/* Actions for REJECTED - can restore */}
                  {activeTab === 'rejected' && (
                    <div className="mt-auto flex items-center gap-2">
                      <span className="status-badge badge-rejected">
                        <X className="w-3.5 h-3.5" />
                        Đã gỡ bỏ
                      </span>
                      <button
                        onClick={() => handleApprove(video.videoId)}
                        className="text-xs font-label text-primary hover:underline"
                      >
                        Khôi phục
                      </button>
                    </div>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}
      {/* Playing Video Modal */}
      {playingVideo && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-background/90 backdrop-blur-md">
          <div className="relative w-full max-w-4xl max-h-screen flex flex-col md:flex-row bg-surface border border-outline-variant/20 rounded-2xl overflow-hidden shadow-2xl animate-in fade-in zoom-in-95 duration-200">
            {/* Video Player */}
            <div className="relative flex-1 bg-black flex items-center justify-center min-h-[50vh] md:min-h-[80vh]">
              {playingVideo.videoUri ? (
                <video
                  src={playingVideo.videoUri}
                  controls
                  autoPlay
                  className="max-w-full max-h-[80vh] w-auto h-auto object-contain"
                />
              ) : (
                <div className="text-on-surface-variant flex flex-col items-center">
                  <Play className="w-16 h-16 mb-4 opacity-50" />
                  <p>Video không khả dụng</p>
                </div>
              )}
            </div>

            {/* Video Details Side Panel */}
            <div className="w-full md:w-80 flex flex-col bg-surface-low border-l border-outline-variant/10">
              <div className="p-4 border-b border-outline-variant/10 flex justify-between items-center bg-surface">
                <h3 className="font-headline font-bold text-on-surface truncate">Chi tiết Video</h3>
                <button
                  onClick={() => setPlayingVideo(null)}
                  className="p-1.5 text-on-surface-variant hover:bg-surface-high hover:text-on-surface rounded-full transition-colors"
                >
                  <X className="w-5 h-5" />
                </button>
              </div>

              <div className="p-4 flex-1 overflow-y-auto space-y-4">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-full bg-primary/20 flex items-center justify-center text-primary font-bold">
                    {playingVideo.username.charAt(0).toUpperCase()}
                  </div>
                  <div>
                    <p className="font-label text-sm text-on-surface font-bold">@{playingVideo.username}</p>
                    <p className="text-xs text-on-surface-variant">{new Date(playingVideo.timestamp).toLocaleString('vi-VN')}</p>
                  </div>
                </div>

                <div className="bg-surface-high/50 p-3 rounded-lg border border-outline-variant/10">
                  <p className="font-body text-sm text-on-surface whitespace-pre-wrap">{playingVideo.description || 'Không có mô tả'}</p>
                </div>

                <div className="grid grid-cols-3 gap-2 text-center py-2">
                  <div className="bg-surface p-2 rounded border border-outline-variant/10">
                    <p className="text-xs text-on-surface-variant mb-1">Lượt thích</p>
                    <p className="font-label font-bold text-on-surface">{playingVideo.totalLikes}</p>
                  </div>
                  <div className="bg-surface p-2 rounded border border-outline-variant/10">
                    <p className="text-xs text-on-surface-variant mb-1">Bình luận</p>
                    <p className="font-label font-bold text-on-surface">{playingVideo.totalComments}</p>
                  </div>
                  <div className="bg-surface p-2 rounded border border-outline-variant/10">
                    <p className="text-xs text-on-surface-variant mb-1">Lượt xem</p>
                    <p className="font-label font-bold text-on-surface">{playingVideo.watchCount}</p>
                  </div>
                </div>
              </div>

              {/* Quick Actions in Player */}
              {user?.role !== 'viewer' && activeTab === 'pending' && (
                <div className="p-4 border-t border-outline-variant/10 flex gap-2 bg-surface">
                  <button
                    onClick={() => {
                      handleApprove(playingVideo.videoId);
                      setPlayingVideo(null);
                    }}
                    className="flex-1 flex items-center justify-center gap-2 py-2.5 bg-secondary/20 text-secondary hover:bg-secondary hover:text-on-secondary font-label text-sm rounded-lg transition-colors border border-secondary/30"
                  >
                    <Check className="w-4 h-4" /> Duyệt
                  </button>
                  <button
                    onClick={() => {
                      setRejectingId(playingVideo.videoId);
                      setPlayingVideo(null);
                    }}
                    className="flex-1 flex items-center justify-center gap-2 py-2.5 bg-error/10 text-error hover:bg-error hover:text-on-error font-label text-sm rounded-lg transition-colors border border-error/20"
                  >
                    <Trash2 className="w-4 h-4" /> Gỡ
                  </button>
                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
