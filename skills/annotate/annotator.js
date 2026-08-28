;(() => {
	if (window.__skillAnnotator) return 'already installed'
	const STORE_KEY = '__skill_annotations'
	// Adopt notes left by any earlier build of this overlay, whatever prefix it
	// used, so a rename never orphans a page's existing pins.
	if (!localStorage.getItem(STORE_KEY)) {
		const legacy = Object.keys(localStorage).find(k => k !== STORE_KEY && /^__.+_annotations$/.test(k))
		if (legacy) localStorage.setItem(STORE_KEY, localStorage.getItem(legacy))
	}
	const load = () => {
		try {
			return JSON.parse(localStorage.getItem(STORE_KEY) || '[]')
		} catch {
			return []
		}
	}
	const save = a => localStorage.setItem(STORE_KEY, JSON.stringify(a))

	const cssPath = el => {
		const parts = []
		while (el && el.nodeType === 1 && el !== document.body) {
			let p = el.tagName.toLowerCase()
			if (el.id) {
				parts.unshift(p + '#' + el.id)
				break
			}
			const cls = [...el.classList].slice(0, 2).join('.')
			if (cls) p += '.' + cls
			const sibs = el.parentElement ? [...el.parentElement.children].filter(c => c.tagName === el.tagName) : []
			if (sibs.length > 1) p += ':nth-of-type(' + (sibs.indexOf(el) + 1) + ')'
			parts.unshift(p)
			el = el.parentElement
		}
		return parts.join(' > ')
	}

	let armed = true

	// Toolbar. innerHTML here and in the editor below is static authored markup
	// only — user note text must never be interpolated into it (notes travel
	// through textarea.value → JSON, pins through textContent).
	const bar = document.createElement('div')
	bar.id = '__fa_bar'
	bar.style.cssText =
		'position:fixed;bottom:16px;right:16px;z-index:2147483647;background:#1a1a1a;color:#eee;border:1px solid #444;border-radius:10px;padding:8px 12px;font:13px system-ui;display:flex;gap:10px;align-items:center;box-shadow:0 4px 16px rgba(0,0,0,.6)'
	bar.innerHTML =
		'<span id="__fa_count"></span><button id="__fa_toggle" style="background:#e8734a;color:#fff;border:0;border-radius:6px;padding:4px 10px;cursor:pointer;font:12px system-ui">Annotating: ON</button>'
	document.body.appendChild(bar)
	const countEl = bar.querySelector('#__fa_count')
	const toggleBtn = bar.querySelector('#__fa_toggle')
	const refreshCount = () => {
		countEl.textContent = load().length + ' note' + (load().length === 1 ? '' : 's')
	}
	refreshCount()
	toggleBtn.addEventListener('click', e => {
		e.stopPropagation()
		armed = !armed
		toggleBtn.textContent = 'Annotating: ' + (armed ? 'ON' : 'OFF')
		toggleBtn.style.background = armed ? '#e8734a' : '#555'
	})

	const drawPin = (n, x, y) => {
		const pin = document.createElement('div')
		pin.className = '__fa_pin'
		pin.textContent = n
		pin.style.cssText =
			'position:absolute;left:' +
			(x - 12) +
			'px;top:' +
			(y - 12) +
			'px;width:24px;height:24px;border-radius:50%;background:#e8734a;color:#fff;font:bold 12px/24px system-ui;text-align:center;z-index:2147483646;box-shadow:0 2px 8px rgba(0,0,0,.5);pointer-events:none'
		document.body.appendChild(pin)
	}

	// redraw pins for this page
	load()
		.filter(a => a.url === location.pathname)
		.forEach(a => drawPin(a.n, a.pageX, a.pageY))

	let editor = null
	const openEditor = (target, pageX, pageY) => {
		if (editor) editor.remove()
		editor = document.createElement('div')
		editor.style.cssText =
			'position:absolute;left:' +
			Math.min(pageX, window.scrollX + innerWidth - 300) +
			'px;top:' +
			(pageY + 14) +
			'px;z-index:2147483647;background:#222;border:1px solid #555;border-radius:10px;padding:10px;width:280px;box-shadow:0 6px 24px rgba(0,0,0,.7);font:13px system-ui;color:#eee'
		editor.innerHTML =
			'<textarea placeholder="What should change here?" style="width:100%;height:64px;background:#111;color:#eee;border:1px solid #444;border-radius:6px;padding:6px;font:13px system-ui;resize:vertical;box-sizing:border-box"></textarea><div style="display:flex;gap:8px;margin-top:8px;justify-content:flex-end"><button data-a="cancel" style="background:#444;color:#eee;border:0;border-radius:6px;padding:4px 10px;cursor:pointer">Cancel</button><button data-a="save" style="background:#e8734a;color:#fff;border:0;border-radius:6px;padding:4px 10px;cursor:pointer">Save</button></div>'
		document.body.appendChild(editor)
		const ta = editor.querySelector('textarea')
		setTimeout(() => ta.focus(), 0)
		editor.addEventListener('mousedown', e => e.stopPropagation(), true)
		editor.addEventListener(
			'click',
			e => {
				e.stopPropagation()
				const a = e.target.getAttribute && e.target.getAttribute('data-a')
				if (a === 'cancel') {
					editor.remove()
					editor = null
				}
				if (a === 'save') {
					const note = ta.value.trim()
					if (!note) {
						editor.remove()
						editor = null
						return
					}
					const all = load()
					const n = all.length + 1
					all.push({
						n,
						note,
						url: location.pathname,
						pageX,
						pageY,
						selector: cssPath(target),
						tag: target.tagName.toLowerCase(),
						text: (target.innerText || '').trim().slice(0, 120),
						ts: new Date().toISOString(),
					})
					save(all)
					drawPin(n, pageX, pageY)
					refreshCount()
					editor.remove()
					editor = null
				}
			},
			true,
		)
	}

	document.addEventListener(
		'click',
		e => {
			if (!armed) return
			if (e.target.closest('#__fa_bar') || (editor && editor.contains(e.target))) return
			e.preventDefault()
			e.stopPropagation()
			openEditor(e.target, e.pageX, e.pageY)
		},
		true,
	)

	window.__skillAnnotator = true
	return 'installed, existing notes: ' + load().length
})()
