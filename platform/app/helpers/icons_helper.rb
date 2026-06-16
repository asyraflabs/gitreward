module IconsHelper
  # Inline SVG icons (currentColor line/solid), ported from the design handoff
  # (reference/components.jsx object `I`). Usage: <%= icon(:repo, 16) %>.
  ICON_DEFAULT_SIZE = {
    repo: 17, arrow: 16, ext: 14, copy: 15, check: 15, wallet: 17,
    dollar: 20, circle_dollar: 20, pin: 20, branch: 20, pull_request: 20, lock: 16, refund: 16
  }.freeze

  ICON_PATHS = {
    repo: %(<path d="M5 4.5A1.5 1.5 0 0 1 6.5 3H19v15H6.5A1.5 1.5 0 0 0 5 19.5z"/><path d="M5 19.5A1.5 1.5 0 0 1 6.5 18H19v3H6.5A1.5 1.5 0 0 1 5 19.5z"/>),
    arrow: %(<path d="M5 12h14M13 6l6 6-6 6"/>),
    ext: %(<path d="M9 5h10v10M19 5 8 16M5 9v10h10"/>),
    copy: %(<rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h8"/>),
    check: %(<path d="m5 12 4.5 4.5L19 7"/>),
    wallet: %(<rect x="3" y="6" width="18" height="13" rx="2.5"/><path d="M3 9h13a2 2 0 0 1 2 2v2a2 2 0 0 1-2 2H3"/><circle cx="16.5" cy="12.5" r="1" fill="currentColor" stroke="none"/>),
    dollar: %(<line x1="12" x2="12" y1="2" y2="22"/><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/>),
    pin: %(<path d="M12 17v5"/><path d="M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z"/>),
    branch: %(<circle cx="6" cy="5" r="2.4"/><circle cx="6" cy="19" r="2.4"/><circle cx="18" cy="7" r="2.4"/><path d="M6 7.4v9.2M18 9.4c0 4-3 5-6 5"/>),
    pull_request: %(<circle cx="5" cy="6" r="3"/><path d="M5 9v12"/><circle cx="19" cy="18" r="3"/><path d="m15 9-3-3 3-3"/><path d="M12 6h5a2 2 0 0 1 2 2v7"/>),
    circle_dollar: %(<circle cx="12" cy="12" r="10"/><path d="M16 8h-6a2 2 0 1 0 0 4h4a2 2 0 1 1 0 4H8"/><path d="M12 18V6"/>),
    lock: %(<rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>),
    refund: %(<path d="M4 9h11a5 5 0 0 1 0 10h-4"/><path d="M8 5 4 9l4 4"/>)
  }.freeze

  def icon(name, size = nil)
    name = name.to_sym
    s = size || ICON_DEFAULT_SIZE.fetch(name, 18)
    tag.svg(ICON_PATHS.fetch(name).html_safe, # rubocop:disable Rails/OutputSafety -- static, internal SVG
            width: s, height: s, viewbox: "0 0 24 24", fill: "none",
            stroke: "currentColor", "stroke-width": 1.9,
            "stroke-linecap": "round", "stroke-linejoin": "round",
            class: "inline-block align-[-0.125em]")
  end

  # GitHub mark (solid, uses currentColor). Separate from `icon` because it's a
  # filled glyph rather than a stroked line icon.
  def github_mark(size = 18)
    path = %(<path fill="currentColor" fill-rule="evenodd" clip-rule="evenodd" d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0 1 12 6.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.02 10.02 0 0 0 22 12.017C22 6.484 17.523 2 12 2Z"/>)
    tag.svg(path.html_safe, # rubocop:disable Rails/OutputSafety -- static, internal SVG
            width: size, height: size, viewbox: "0 0 24 24", fill: "none",
            class: "inline-block align-[-0.125em]")
  end

  # The GitReward brand mark (orange star) from the marketing site header.
  def gitreward_logo(size = 26)
    path = %(<path fill="#F97316" d="M372.098 318.592 459.239 128.838C468.707 108.222 489.314 95.009 512 95.009C534.686 95.009 555.293 108.222 564.761 128.838L663.626 344.123 898.926 371.623C921.458 374.256 940.393 389.772 947.403 411.348C954.413 432.923 948.215 456.605 931.534 471.98L757.337 632.534 803.894 864.815C808.352 887.058 799.447 909.86 781.094 923.195C762.741 936.529 738.302 937.952 718.525 926.839L512 810.781 305.475 926.839C285.698 937.952 261.259 936.529 242.906 923.195C224.553 909.86 215.648 887.058 220.106 864.815L266.663 632.534 92.466 471.98C75.785 456.605 69.587 432.923 76.597 411.348C83.607 389.772 102.542 374.256 125.074 371.623L353.125 344.97 465.037 456.882C461.516 463.99 459.536 471.995 459.536 480.46C459.536 504.255 475.182 524.424 496.735 531.232L496.735 664.979C475.182 671.787 459.536 691.956 459.536 715.751C459.536 745.131 483.389 768.984 512.769 768.984C542.149 768.984 566.002 745.131 566.002 715.751C566.002 691.956 550.356 671.787 528.803 664.979L528.803 531.232C531.41 530.408 533.93 529.389 536.347 528.192L597.483 589.328C594.986 595.49 593.61 602.228 593.61 609.285C593.61 638.665 617.463 662.518 646.843 662.518C676.223 662.518 700.076 638.665 700.076 609.285C700.076 579.905 676.223 556.052 646.843 556.052C636.231 556.052 626.34 559.164 618.032 564.525L559.488 505.982C563.64 498.404 566.002 489.706 566.002 480.46C566.002 451.08 542.149 427.227 512.769 427.227C503.523 427.227 494.825 429.589 487.247 433.741L372.098 318.592Z"/>)
    tag.svg(path.html_safe, # rubocop:disable Rails/OutputSafety
            width: size, height: size, viewbox: "0 0 1024 1024",
            xmlns: "http://www.w3.org/2000/svg", "fill-rule": "evenodd", "clip-rule": "evenodd")
  end
end
