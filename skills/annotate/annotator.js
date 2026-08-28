;(() => {
	const GLOBAL_KEY = '__skillAnnotator'
	const STORE_KEY = '__skill_annotations'
	const installed = window[GLOBAL_KEY]
	if (installed?.host?.isConnected) return 'already installed'

	const storageError = (action, error) =>
		new Error(
			`Annotation overlay could not ${action} localStorage: ${error instanceof Error ? error.message : String(error)}. Enable site storage and try again.`,
		)

	const readStored = () => {
		let raw
		try {
			raw = localStorage.getItem(STORE_KEY)
		} catch (error) {
			throw storageError('read', error)
		}
		if (raw === null) return { all: [], notes: [], skipped: 0 }
		let notes
		try {
			notes = JSON.parse(raw)
		} catch {
			throw new Error(
				`Annotation data in localStorage key ${STORE_KEY} is not valid JSON. Back it up or remove that key, then inject the overlay again.`,
			)
		}
		if (!Array.isArray(notes)) {
			throw new Error(
				`Annotation data in localStorage key ${STORE_KEY} is not an array. Back it up or remove that key, then inject the overlay again.`,
			)
		}
		const validNotes = []
		let skipped = 0
		notes.forEach(note => {
			const valid =
				note &&
				typeof note === 'object' &&
				Number.isFinite(note.n) &&
				typeof note.note === 'string' &&
				typeof note.url === 'string' &&
				Number.isFinite(note.pageX) &&
				Number.isFinite(note.pageY) &&
				typeof note.selector === 'string' &&
				typeof note.tag === 'string' &&
				typeof note.text === 'string' &&
				typeof note.ts === 'string'
			if (valid) validNotes.push(note)
			else skipped++
		})
		return { all: notes, notes: validNotes, skipped }
	}
	const load = () => readStored().notes

	const save = notes => {
		try {
			localStorage.setItem(STORE_KEY, JSON.stringify(notes))
		} catch (error) {
			throw storageError('write to', error)
		}
	}

	const initial = readStored()
	const initialNotes = initial.notes
	const host = document.createElement('div')
	host.setAttribute('data-skill-annotator', '')
	const root = host.attachShadow({ mode: 'open' })
	const style = document.createElement('style')
	style.textContent = `
		:host { all: initial !important; position: fixed !important; inset: 0 auto auto 0 !important; width: 0 !important; height: 0 !important; overflow: visible !important; z-index: 2147483647 !important; color-scheme: dark !important; }
		*, *::before, *::after { box-sizing: border-box; }
		.toolbar, .editor, .pin { font-family: system-ui, sans-serif; }
		.toolbar { position: fixed; right: 16px; bottom: 16px; display: flex; gap: 10px; align-items: center; padding: 8px 12px; color: #eee; background: #1a1a1a; border: 1px solid #555; border-radius: 10px; box-shadow: 0 4px 16px rgb(0 0 0 / 60%); font-size: 13px; line-height: 1.4; pointer-events: auto; }
		button { appearance: none; border: 1px solid transparent; border-radius: 6px; padding: 5px 10px; color: #fff; background: #555; font: 600 12px/1.3 system-ui, sans-serif; cursor: pointer; }
		button[data-armed="true"], button.save { background: #c84f28; }
		button:hover { filter: brightness(1.15); }
		button:focus-visible, textarea:focus-visible { outline: 3px solid #8ac8ff; outline-offset: 2px; }
		.pin { position: fixed; width: 24px; height: 24px; color: #fff; background: #c84f28; border-radius: 50%; box-shadow: 0 2px 8px rgb(0 0 0 / 50%); font-size: 12px; font-weight: 700; line-height: 24px; text-align: center; pointer-events: none; }
		.editor { position: fixed; width: min(280px, calc(100vw - 16px)); padding: 10px; color: #eee; background: #222; border: 1px solid #666; border-radius: 10px; box-shadow: 0 6px 24px rgb(0 0 0 / 70%); font-size: 13px; line-height: 1.4; pointer-events: auto; }
		.editor label { display: block; margin-bottom: 6px; font-weight: 600; }
		.editor textarea { display: block; width: 100%; min-height: 72px; padding: 7px; resize: vertical; color: #eee; background: #111; border: 1px solid #666; border-radius: 6px; font: 13px/1.4 system-ui, sans-serif; }
		.actions { display: flex; gap: 8px; justify-content: flex-end; margin-top: 8px; }
		.error { min-height: 1.4em; margin: 6px 0 0; color: #ffb4a2; }
	`
	root.appendChild(style)

	const toolbar = document.createElement('div')
	toolbar.className = 'toolbar'
	toolbar.setAttribute('role', 'toolbar')
	toolbar.setAttribute('aria-label', 'Page annotations')
	const count = document.createElement('span')
	count.setAttribute('aria-live', 'polite')
	const toggle = document.createElement('button')
	toggle.type = 'button'
	toolbar.append(count, toggle)
	root.appendChild(toolbar)
	document.documentElement.appendChild(host)

	let armed = true
	let editor = null

	const refreshCount = () => {
		const stored = readStored()
		const total = stored.notes.length
		count.textContent = `${total} note${total === 1 ? '' : 's'}${stored.skipped ? `, ${stored.skipped} invalid` : ''}`
	}

	const refreshToggle = () => {
		toggle.dataset.armed = String(armed)
		toggle.setAttribute('aria-pressed', String(armed))
		toggle.textContent = `Annotating: ${armed ? 'ON' : 'OFF'}`
		toggle.title = armed ? 'Turn off to use the page normally' : 'Turn on to add notes'
	}

	const positionPin = pin => {
		pin.style.left = `${Number(pin.dataset.pageX) - window.scrollX - 12}px`
		pin.style.top = `${Number(pin.dataset.pageY) - window.scrollY - 12}px`
	}

	const drawPin = note => {
		if (!Number.isFinite(note.n) || !Number.isFinite(note.pageX) || !Number.isFinite(note.pageY)) {
			throw new Error(
				`Annotation ${String(note.n ?? '?')} has invalid coordinates. Back up or repair localStorage key ${STORE_KEY}, then inject the overlay again.`,
			)
		}
		const pin = document.createElement('div')
		pin.className = 'pin'
		pin.dataset.pageX = String(note.pageX)
		pin.dataset.pageY = String(note.pageY)
		pin.textContent = String(note.n)
		pin.setAttribute('aria-hidden', 'true')
		positionPin(pin)
		root.appendChild(pin)
	}

	const clearPins = () => root.querySelectorAll('.pin').forEach(pin => pin.remove())
	const refreshPins = () => root.querySelectorAll('.pin').forEach(positionPin)
	const redrawPins = () => {
		clearPins()
		load()
			.filter(note => note.url === location.pathname)
			.forEach(drawPin)
		refreshCount()
	}

	const cssPath = element => {
		const parts = []
		let current = element
		while (current?.nodeType === Node.ELEMENT_NODE) {
			let part = current.tagName.toLowerCase()
			if (current.id && globalThis.CSS?.escape) {
				parts.unshift(`${part}#${CSS.escape(current.id)}`)
				break
			}
			const safeClasses = [...current.classList]
				.filter(name => /^-?[_a-zA-Z]+[_a-zA-Z0-9-]*$/.test(name))
				.slice(0, 2)
			if (safeClasses.length) part += `.${safeClasses.join('.')}`
			const siblings = current.parentElement
				? [...current.parentElement.children].filter(child => child.tagName === current.tagName)
				: []
			if (siblings.length > 1) part += `:nth-of-type(${siblings.indexOf(current) + 1})`
			parts.unshift(part)
			if (current === document.body || current === document.documentElement) break
			current = current.parentElement
		}
		return parts.join(' > ')
	}

	const closeEditor = () => {
		if (!editor) return
		editor.remove()
		editor = null
		toggle.focus()
	}

	const openEditor = (target, event) => {
		closeEditor()
		const panel = document.createElement('div')
		panel.className = 'editor'
		panel.setAttribute('role', 'dialog')
		panel.setAttribute('aria-label', 'Add annotation')
		panel.style.left = `${Math.max(8, Math.min(event.clientX, window.innerWidth - 288))}px`
		panel.style.top = `${Math.max(8, Math.min(event.clientY + 14, window.innerHeight - 180))}px`

		const label = document.createElement('label')
		label.textContent = 'What should change here?'
		const textarea = document.createElement('textarea')
		const error = document.createElement('p')
		error.className = 'error'
		error.setAttribute('role', 'status')
		const actions = document.createElement('div')
		actions.className = 'actions'
		const cancel = document.createElement('button')
		cancel.type = 'button'
		cancel.textContent = 'Cancel'
		const saveButton = document.createElement('button')
		saveButton.type = 'button'
		saveButton.className = 'save'
		saveButton.textContent = 'Save'
		label.appendChild(textarea)
		actions.append(cancel, saveButton)
		panel.append(label, error, actions)
		root.appendChild(panel)
		editor = panel

		const saveNote = () => {
			const note = textarea.value.trim()
			if (!note) {
				error.textContent = 'Enter a note before saving.'
				textarea.focus()
				return
			}
			let storedData
			try {
				storedData = readStored()
			} catch (storageIssue) {
				error.textContent = storageIssue instanceof Error ? storageIssue.message : String(storageIssue)
				return
			}
			const n = storedData.notes.reduce((highest, item) => Math.max(highest, Number(item.n) || 0), 0) + 1
			const stored = {
				n,
				note,
				url: location.pathname,
				pageX: event.pageX,
				pageY: event.pageY,
				selector: cssPath(target),
				tag: target.tagName.toLowerCase(),
				text: (target.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 120),
				ts: new Date().toISOString(),
			}
			storedData.all.push(stored)
			try {
				save(storedData.all)
			} catch (storageIssue) {
				error.textContent = storageIssue instanceof Error ? storageIssue.message : String(storageIssue)
				return
			}
			drawPin(stored)
			refreshCount()
			closeEditor()
		}

		cancel.addEventListener('click', closeEditor)
		saveButton.addEventListener('click', saveNote)
		panel.addEventListener('keydown', keyEvent => {
			if (keyEvent.key === 'Escape') {
				keyEvent.preventDefault()
				closeEditor()
			} else if ((keyEvent.metaKey || keyEvent.ctrlKey) && keyEvent.key === 'Enter') {
				keyEvent.preventDefault()
				saveNote()
			}
		})
		textarea.focus()
	}

	const onPageClick = event => {
		if (!armed || event.composedPath().includes(host)) return
		const target = event.composedPath().find(node => node instanceof Element)
		if (!target) return
		event.preventDefault()
		event.stopPropagation()
		openEditor(target, event)
	}

	toggle.addEventListener('click', () => {
		armed = !armed
		if (!armed) closeEditor()
		refreshToggle()
	})
	root.addEventListener('keydown', event => event.stopPropagation())
	document.addEventListener('click', onPageClick, true)
	window.addEventListener('scroll', refreshPins, { passive: true })
	window.addEventListener('resize', refreshPins)

	const api = {
		host,
		clear() {
			try {
				localStorage.removeItem(STORE_KEY)
			} catch (error) {
				throw storageError('clear', error)
			}
			redrawPins()
		},
		refresh: redrawPins,
		destroy() {
			document.removeEventListener('click', onPageClick, true)
			window.removeEventListener('scroll', refreshPins)
			window.removeEventListener('resize', refreshPins)
			host.remove()
			delete window[GLOBAL_KEY]
		},
	}
	window[GLOBAL_KEY] = api
	refreshToggle()
	initialNotes.filter(note => note.url === location.pathname).forEach(drawPin)
	refreshCount()
	return `installed, existing notes: ${initialNotes.length}${initial.skipped ? `, skipped invalid: ${initial.skipped}` : ''}`
})()
