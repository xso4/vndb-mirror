CREATE TYPE ipinfo AS (
    ip inet,
    country text,
    asn integer,
    as_name text,
    anonymous_proxy boolean,
    sattelite_provider boolean,
    anycast boolean,
    drop boolean
);

ALTER TABLE audit_log ALTER COLUMN by_ip TYPE ipinfo USING ROW(by_ip,null,null,null,null,null,null,null);
ALTER TABLE reports   ALTER COLUMN ip    TYPE ipinfo USING CASE WHEN ip IS NULL THEN NULL ELSE ROW(ip,null,null,null,null,null,null,null)::ipinfo END;

ALTER TABLE users_shadow ALTER COLUMN ip DROP DEFAULT;
ALTER TABLE users_shadow ALTER COLUMN ip DROP NOT NULL;
ALTER TABLE users_shadow ALTER COLUMN ip TYPE ipinfo USING CASE WHEN ip = '0.0.0.0' THEN NULL ELSE ROW(ip,null,null,null,null,null,null,null)::ipinfo END;
