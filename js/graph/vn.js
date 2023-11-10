// TODO:
// - VN cards on hover
widget('VNGraph', initVnode => {
    const {data} = initVnode.attrs;

    let nodes, links;

    const hasUnoff = !!data.rels.find(([,,,o]) => !o);
    const foundRelTypes = Object.fromEntries(data.rels.map(([,,r,]) => [r,true]));
    // Excludes reverse relations, as those are filtered on the backend.
    const relTypes = vndbTypes.vnRelation.filter(
        ([id,lbl,rev,pref]) => foundRelTypes[id] && (id === rev || pref)
    );

    let optMain = data.main;
    let optOfficial = false;
    let optTypes = Object.fromEntries(relTypes);
    let optDistance = 9999;
    let maxDistance = 0;

    const imgprefs = [
        { id: 0, field: 'sexual', label: 'Safe' },
        { id: 1, field: 'sexual', label: 'Suggestive' },
        { id: 2, field: 'sexual', label: 'Explicit' },
        { id: 3, field: 'violence', label: 'Tame' },
        { id: 4, field: 'violence', label: 'Violent' },
        { id: 5, field: 'violence', label: 'Brutal' },
    ];
    const dsImgPref = new DS({
        list: (a,b,cb) => cb(imgprefs),
        view: obj => obj.label,
    }, {
        onselect: obj => data[obj.field] = obj.id % 3,
        checked: obj => data[obj.field] === obj.id % 3,
        width: 130, nosearch: true,
    });
    const needImgPrefs = !!data.nodes.find(n => n.image && (n.image[1] > 0 || n.image[2] > 0));

    let svg;
    let autoscale = true;
    let height = 100, width = 100;
    const resize = () => {
        height = Math.max(200, window.innerHeight - 40);
        width = svg.clientWidth;
        m.redraw();
    };
    window.addEventListener('resize', resize);

    // TODO: Tuning, this simulation is somewhat unstable for large graphs
    const simulationLinks = d3.forceLink().distance(500).id(n => n.id);
    const simulation = d3.forceSimulation()
        //.alphaMin(0.001)
        //.alphaDecay(0.001)
        .force('link', simulationLinks)
        .force('charge', d3.forceManyBody().strength(-5000))
        //.force('collision', d3.forceCollide(100))
        .force('x', d3.forceX().strength(0.1))
        .force('y', d3.forceY().strength(0.1))
        .on('tick', () => {
            let minX = 0, maxX = 0, minY = 0, maxY = 0;
            nodes.forEach(n => {
                if (n.x < minX) minX = n.x;
                if (n.y < minY) minY = n.y;
                if (n.x > maxX) maxX = n.x;
                if (n.y > maxY) maxY = n.y;
            });
            const margin = 100;
            zoom.translateExtent([[minX-margin,minY-margin],[maxX+margin,maxY+margin]]);
            const scale = Math.min(1, width / (maxX - minX + 2*margin), height / (maxY - minY + 2*margin));
            zoom.scaleExtent([scale, 1]);
            // TODO: Even if autoscale is off, we might want to ensure the
            // current view fits inside the given Extents. Might not be the
            // case anymore after dragging.
            if (autoscale) {
                const obj = d3.select(svg);
                zoom.scaleTo(obj, scale);
                zoom.translateTo(obj, 0, 0);
            }
            m.redraw();
        });

    const nodeById = Object.fromEntries(data.nodes.map(n => ([n.id,n])));
    const linkObjects = data.rels.map(([a,b,relation,official]) => ({source: nodeById[a], target: nodeById[b], relation, official}));
    const setGraph = () => {
        links = linkObjects.filter(l => (!optOfficial || l.official) && optTypes[l.relation]);
        data.nodes.forEach(n => {n.included = false; n.links = []});
        links.forEach(({source,target}) => {
            source.links.push(target);
            target.links.push(source);
        });
        const traverse = dist => n => {
            if (n.included) return;
            if (maxDistance < dist) maxDistance = dist;
            n.included = true;
            if (dist < optDistance) n.links.forEach(traverse(dist+1));
        };
        traverse(0)(nodeById[optMain]);
        data.nodes.forEach(n => { delete(n.links); if (!n.included) { delete(n.x); delete(n.y) }});
        nodes = data.nodes.filter(n => n.included);
        links = links.filter(({source,target}) => source.included && target.included);
        autoscale = true;
        simulation.nodes(nodes);
        simulationLinks.links(links);
        simulation.alpha(1).restart();
    };
    setGraph();
    if (optDistance > maxDistance) optDistance = maxDistance;

    const drag = vnode => d3.select(vnode.dom).call(d3.drag()
        .subject(nodes[vnode.dom.dataset.nodeidx])
        .on("start", ev => {
            autoscale = false;
            if (!ev.active) simulation.alphaTarget(0.3).restart();
            ev.subject.fx = ev.subject.x;
            ev.subject.fy = ev.subject.y;
        }).on("drag", ev => {
            ev.subject.fx = ev.x;
            ev.subject.fy = ev.y;
        }).on("end", ev => {
            if (!ev.active) simulation.alphaTarget(0);
            ev.subject.fx = null;
            ev.subject.fy = null;
        }));

    // Should be called whenever opt* variables are changed.
    const save = reload => {
        const types = relTypes.map(([id]) => optTypes[id] ? id : null).filter(v=>v);
        const opts = [
            optMain === data.main ? null : optMain,
            optOfficial ? 'o1' : null,
            optDistance === maxDistance ? null : 'd'+optDistance,
            types.length === relTypes.length ? null : types,
        ].flat().filter(v => v);
        history.replaceState(null, "", '#'+opts.join(','));
        if (reload) {
            setGraph();
            simulation.restart();
        }
    };

    if (location.hash.length > 1) {
        let types = {};
        location.hash.substr(1).split(/,/).forEach(s => {
            if (s === 'o1') optOfficial = true;
            else if (s === 'o0') optOfficial = false;
            else if (s.match(/^d[0-9]+$/)) optDistance = 1*s.substr(1);
            else if (s.match(/^v[0-9]+$/)) optMain = s;
            else if (Object.fromEntries(relTypes)[s]) types[s] = true;
        });
        if (Object.keys(types).length) optTypes = types;
        save(true);
    }

    const newmain = ev => {
        optMain = nodes[event.target.dataset.nodeidx].id;
        save(optDistance < maxDistance);
    };
    const noscale = () => autoscale = false;

    const dsTypes = new DS({
        list: (a,b,cb) => cb(relTypes.map(([id,label]) => ({id,label}))),
        view: obj => obj.label
    }, {
        onselect: (obj, v) => { optTypes[obj.id] = v; save(true); },
        checked: obj => optTypes[obj.id],
        width: 160, nosearch: true,
    });

    const zoom = d3.zoom()
        .on("zoom", ev => {
            svg.childNodes[0].setAttribute('transform', ev.transform);
            m.redraw(); // Only necessary to update the debug info, could be left out as an optimization
        });

    const view = () => m('div#vn-graph',
        m('div', { oncreate: v => v.dom.scrollIntoView() },
            m('small', (() => {
                const t = svg && d3.zoomTransform(svg);
                return t ? 'a=' + simulation.alpha().toFixed(3) + ' x=' + t.x.toFixed(1) + ' y=' + t.y.toFixed(1) + ' k=' + t.k.toFixed(3) + ' d='+optDistance : null;
            })()),
            m('div',
                m('input[type=range][min=0]', {
                    max: maxDistance, value: optDistance,
                    oninput: ev => { optDistance = ev.target.value; save(true) },
                    style: { width: maxDistance <= 3 ? '100px' : maxDistance <= 10 ? '150px' : '200px' },
                }),
                hasUnoff ? m('label',
                    m('input[type=checkbox]', { checked: optOfficial, oninput: ev => { optOfficial = ev.target.checked; save(true); }}),
                    ' official only '
                ) : null,
                m(DS.Button, {ds: dsTypes}, 'relations'),
                needImgPrefs ? m(DS.Button, {ds: dsImgPref}, 'nsfw') : null,
            ),
        ),
        m('svg', {
                height, viewBox: '0 0 '+width+' '+height,
                oncreate: v => { svg = v.dom; resize(); d3.select(svg).call(zoom).on("dblclick.zoom", null); },
                onmousedown: () => autoscale = false,
                onwheel: () => autoscale = false,
            }, m('g',
            m('defs',
                // TODO: Better handle nsfw or missing images; blurhash or something? Title?
                nodes.map(n => m('pattern', { id: 'p'+n.id, width: '100%', height: '100%' },
                    n.image && n.image[1] <= data.sexual && n.image[2] <= data.violence
                    ? m('image', { href: n.image[0], x: -20, y: -20, width: 240, height: 240 })
                    : m('circle', { r: 80, cx: 100, cy: 100 })
                )),
            ),
            // TODO: stroke width depending on zoom level
            // TODO: arrows/icons to indicate relation type
            m('g.edges', links.map(l => m('line', {
                key: l.source.id+l.target.id,
                x1: l.source.x, y1: l.source.y,
                x2: l.target.x, y2: l.target.y,
                'stroke-dasharray': l.official ? 1 : '3,10',
            }))),
            m('g.main', nodes.filter(n => n.id === optMain).map(n => m('circle', { r: 110, cx: n.x, cy: n.y }))),
            m('g.nodes', nodes.map((n,i) => m('circle', {
                key: n.id,
                'data-nodeidx': i, oncreate: drag, onclick: newmain,
                r: 100, cx: n.x, cy: n.y,
                fill: 'url(#p'+n.id+')',
            }))),
        )),
    );
    return {view};
});
