widget('VNGraph', initVnode => {
    const {data} = initVnode.attrs;

    let nodes, links;
    let optOfficial = false;
    const hasUnoff = !!data.rels.find(([,,,o]) => !o);

    const foundRelTypes = Object.fromEntries(data.rels.map(([,,r,]) => [r,true]));
    // Excludes reverse relations, as those are filtered on the backend.
    const relTypes = vndbTypes.vnRelation.filter(
        ([id,lbl,rev,pref]) => foundRelTypes[id] && (id === rev || pref)
    );

    let optTypes = Object.fromEntries(relTypes);
    let dsTypes = new DS({
        list: (a,b,cb) => cb(relTypes.map(([id,label]) => ({id,label}))),
        view: obj => obj.label
    }, {
        onselect: (obj, v) => {
            optTypes[obj.id] = v;
            setGraph();
            simulation.restart();
        },
        checked: obj => optTypes[obj.id],
        width: 160, nosearch: true,
    });

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
            //minX = maxX = minY = maxY = 0;
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
        const traverse = n => {
            n.included = true;
            n.links.filter(x => !x.included).forEach(traverse);
        };
        traverse(nodeById[data.main]);
        data.nodes.forEach(n => { delete(n.links); if (!n.included) { delete(n.x); delete(n.y) }});
        nodes = data.nodes.filter(n => n.included);
        autoscale = true;
        simulation.nodes(nodes);
        simulationLinks.links(links);
        simulation.alpha(1).restart();
    };
    setGraph();

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

    const newmain = ev => data.main = nodes[event.target.dataset.nodeidx].id;

    // TODO: Disable autoscale on *user*-initiated zoom. The "start" event also triggers by the autoscale code itself. -.-
    const zoom = d3.zoom()
        .on("zoom", ev => svg.childNodes[0].setAttribute('transform', ev.transform));

    const view = () => m('div#vn-graph',
        m('div', {
            oncreate: v => v.dom.scrollIntoView(),
        },
            hasUnoff ? m('label',
                m('input[type=checkbox]', { checked: optOfficial, oninput: ev => { optOfficial = ev.target.checked; setGraph(); simulation.restart() }}),
                ' official only '
            ) : null,
            m(DS.Button, {ds: dsTypes}, 'relations'),
        ),
        m('svg', {
                height, viewBox: '0 0 '+width+' '+height,
                oncreate: v => { svg = v.dom; resize(); d3.select(svg).call(zoom) },
            },
            m('g',
                // TODO: stroke width depending on zoom level
                // TODO: arrows/icons to indicate relation type
                m('g.edges', links.map(l => m('line', {
                    key: l.source.id+l.target.id,
                    x1: l.source.x, y1: l.source.y,
                    x2: l.target.x, y2: l.target.y,
                    'stroke-dasharray': l.official ? 1 : '3,10',
                }))),
                m('g.nodes', nodes.map((n,i) => m('circle', {
                    key: n.id, title: n.title,
                    class: n.id === data.main ? 'selected' : null,
                    'data-nodeidx': i, oncreate: drag, ondblclick: newmain,
                    r: 50, cx: n.x, cy: n.y
                }))),
            ),
        ),
    );
    return {view};
});
