-- Fix RPCs to accept p_radius for backward compatibility with old APKs

CREATE OR REPLACE FUNCTION public.get_popular_near_you_v2(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_radius DOUBLE PRECISION DEFAULT 10000
)
RETURNS JSON AS $$
BEGIN
    RETURN public.get_popular_near_you_v2(p_lat, p_lng);
END;
$$ LANGUAGE plpgsql STABLE;


CREATE OR REPLACE FUNCTION public.get_nearby_vendors_v24(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_radius DOUBLE PRECISION DEFAULT 10000
)
RETURNS JSON AS $$
BEGIN
    RETURN public.get_nearby_vendors_v24(p_lat, p_lng);
END;
$$ LANGUAGE plpgsql STABLE;

CREATE OR REPLACE FUNCTION public.get_nearby_vendors_v23(
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_radius DOUBLE PRECISION DEFAULT 10000
)
RETURNS JSON AS $$
BEGIN
    RETURN public.get_nearby_vendors_v24(p_lat, p_lng); -- fallback to v24
END;
$$ LANGUAGE plpgsql STABLE;

-- Permissions
GRANT EXECUTE ON FUNCTION public.get_popular_near_you_v2(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_nearby_vendors_v24(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_nearby_vendors_v23(DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION) TO anon, authenticated, service_role;
