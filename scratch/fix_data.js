const https = require('https');

const supabaseUrl = 'https://dxqcruvarqgnscenixzf.supabase.co';
const supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImR4cWNydXZhcnFnbnNjZW5peHpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjgwMjQ2NzksImV4cCI6MjA4MzYwMDY3OX0.2Z_DubJZM0p_aIC_1-H_LuZIrf8twPxqLbURw3rrHxY';

function request(path, method = 'GET', body = null) {
    return new Promise((resolve, reject) => {
        const url = new URL(path, supabaseUrl);
        const options = {
            method,
            headers: {
                'apikey': supabaseKey,
                'Authorization': `Bearer ${supabaseKey}`,
                'Content-Type': 'application/json'
            }
        };

        const req = https.request(url, options, (res) => {
            let data = '';
            res.on('data', (chunk) => data += chunk);
            res.on('end', () => {
                if (res.statusCode >= 400) reject(data);
                else resolve(data ? JSON.parse(data) : null);
            });
        });

        req.on('error', reject);
        if (body) req.write(JSON.stringify(body));
        req.end();
    });
}

async function run() {
    console.log(">>> [FIX] Checking tables...");
    try {
        const banners = await request('/rest/v1/banners?select=*&limit=1');
        if (banners && banners.length > 0) {
            console.log("Columns:", Object.keys(banners[0]));
        } else {
            console.log("No banners found to check columns.");
        }

        if (true) { // Force insert with standard columns first
            console.log(">>> [FIX] Inserting Premium Banners...");
            const newBanners = [
            {
                title: 'AUTHENTIC\nHYDERABADI BIRYANI',
                subtitle: 'Slow cooked to perfection',
                image_url: 'https://img.icons8.com/color/512/biryani.png',
                priority: 10,
                is_active: true
            },
            {
                title: 'SOUTH INDIAN\nBREAKFAST SPECIAL',
                subtitle: 'Ghee Podi Dosa & Filter Coffee',
                image_url: 'https://img.icons8.com/color/512/dosa.png',
                priority: 9,
                is_active: true
            },
            {
                title: 'FASTEST\nFREE DELIVERY',
                subtitle: 'Orders above ₹299',
                image_url: 'https://img.icons8.com/color/512/delivery-scooter.png',
                priority: 8,
                is_active: true
            }
        ];

        for (const b of newBanners) {
            await request('/rest/v1/banners', 'POST', b);
        }
        console.log("✅ Banners Inserted Successfully");
        }

        console.log(">>> [FIX] Checking Categories...");
        const categories = await request('/rest/v1/categories?select=*');
        console.log("Current Categories:", categories.length);
        
        if (categories.length === 0) {
            console.log(">>> [FIX] Seeding Categories...");
            const catSeed = [
                { name: 'Biryani', image_url: 'https://img.icons8.com/color/144/biryani.png', priority: 10 },
                { name: 'Fast Food', image_url: 'https://img.icons8.com/color/144/hamburger.png', priority: 9 },
                { name: 'Tiffins', image_url: 'https://img.icons8.com/color/144/dosa.png', priority: 8 },
                { name: 'Thali', image_url: 'https://img.icons8.com/color/144/thali.png', priority: 7 },
                { name: 'Sweets', image_url: 'https://img.icons8.com/color/144/cupcake.png', priority: 6 },
                { name: 'Drinks', image_url: 'https://img.icons8.com/color/144/orange-juice.png', priority: 5 }
            ];
            for (const c of catSeed) {
                await request('/rest/v1/categories', 'POST', c);
            }
            console.log("✅ Categories Seeded Successfully");
        }

    } catch (e) {
        console.error("❌ Error:", e);
    }
}

run();
