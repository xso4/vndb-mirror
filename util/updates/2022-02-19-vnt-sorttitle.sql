DROP VIEW vnt;
CREATE VIEW vnt AS SELECT v.*, COALESCE(vo.latin, vo.title) AS title, COALESCE(vo.latin, vo.title) AS sorttitle, CASE WHEN vo.latin IS NULL THEN '' ELSE vo.title END AS alttitle FROM vn v JOIN vn_titles vo ON vo.id = v.id AND vo.lang = v.olang;
