
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import '../supabase_config.dart';

class BannerCarousel extends StatefulWidget {
  const BannerCarousel({super.key});

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  final PageController _controller = PageController();
  int _currentIndex = 0;
  List<Map<String, dynamic>> _banners = [
    {
      'title': 'FREE DELIVERY',
      'subtitle': 'On your first 3 orders!',
      'image_url': 'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=400&q=80',
      'bg_color': '#E8F5E9',
    },
    {
      'title': '50% OFF TODAY',
      'subtitle': 'Explore premium restaurants',
      'image_url': 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=400&q=80',
      'bg_color': '#FFF3E0',
    },
    {
      'title': 'UNIV SPECIALS',
      'subtitle': 'Authentic home-cooked meals',
      'image_url': 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=400&q=80',
      'bg_color': '#F3E5F5',
    },
  ];
  bool _loading = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_banners.isNotEmpty && _controller.hasClients) {
        final next = (_currentIndex + 1) % _banners.length;
        _controller.animateToPage(next, duration: const Duration(milliseconds: 800), curve: Curves.easeInOutCubic);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final res = await SupabaseConfig.client
          .from('banners')
          .select('*')
          .eq('is_active', true)
          .order('priority', ascending: false);
      
      List<Map<String, dynamic>> fetched = List<Map<String, dynamic>>.from(res ?? []);
      
      if (fetched.isEmpty) {
        fetched = [
          {
            'title': 'FREE DELIVERY',
            'subtitle': 'On your first 3 orders!',
            'image_url': 'https://images.unsplash.com/photo-1513104890138-7c749659a591?w=400&q=80',
            'bg_color': '#E8F5E9',
          },
          {
            'title': '50% OFF TODAY',
            'subtitle': 'Explore premium restaurants',
            'image_url': 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=400&q=80',
            'bg_color': '#FFF3E0',
          },
          {
            'title': 'UNIV SPECIALS',
            'subtitle': 'Authentic home-cooked meals',
            'image_url': 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=400&q=80',
            'bg_color': '#F3E5F5',
          },
        ];
      }

      if (mounted) {
        setState(() {
          _banners = fetched;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() {
        _banners = [
           {
            'title': 'UNIV FOODS',
            'subtitle': 'Delicious meals delivered fast',
            'image_url': 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=400&q=80',
            'bg_color': '#F1F8F1',
          }
        ];
        _loading = false;
      });
    }
  }

  void _onBannerClick(Map<String, dynamic> banner) async {
    final itemId = banner['item_id'];
    final vendorId = banner['vendor_id'];

    if (itemId != null) {
      try {
        final res = await SupabaseConfig.client.from('products').select('*').eq('id', itemId).single();
        if (mounted) {
          Navigator.pushNamed(context, '/product_detail', arguments: res);
        }
      } catch (e) {
        debugPrint("Error clicking item banner: $e");
      }
    } else if (vendorId != null) {
      try {
        final res = await SupabaseConfig.client.from('vendors').select('*').eq('id', vendorId).single();
        if (mounted) {
          Navigator.pushNamed(context, '/menu', arguments: res);
        }
      } catch (e) {
        debugPrint("Error clicking vendor banner: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()));
    if (_banners.isEmpty) return const SizedBox();

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemCount: _banners.length,
            itemBuilder: (context, i) => GestureDetector(
              onTap: () => _onBannerClick(_banners[i]),
              child: _buildItem(_banners[i])
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_banners.length, (i) => Container(
            width: 8, height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: _currentIndex == i ? const Color(0xFFFF6D00) : Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          )),
        ),
      ],
    );
  }
  Widget _buildItem(Map<String, dynamic> banner) {
    final bgColor = Color(int.parse((banner['bg_color'] ?? '#F1F8F1').replaceAll('#', '0xFF')));
    final rawImage = banner['image_url'] ?? banner['image'] ?? '';
    final imageUrl = SupabaseConfig.imageUrl(rawImage);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            children: [
              Expanded(
                flex: 6,
                child: SizedBox(
                  width: double.infinity,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Container(color: Colors.grey[200]),
                  ),
                ),
              ),
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              banner['title'] ?? '',
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                color: Colors.black87,
                                height: 1.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              banner['subtitle'] ?? '',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: Colors.black54,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          banner['action_text'] ?? 'ORDER NOW',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
