# Flipkart_Warehouse_Builder_v3.rb
# Flipkart-style fulfilment centre in SketchUp (units: metres).
# NEW in v3: 8 loading docks (DOCK 1-8) on the right-hand wall, each with a
#   roll-up door, dock leveller, number sign and a truck + trailer parked at it,
#   plus a paved truck yard outside.
# From v2:
#   - Outer walls (semi-transparent) with an entrance gap
#   - Front-wall sign "FLIPKART FULFILMENT CENTRE"
#   - Zone names: coloured floor patch + floor text + overhead banner on posts
#   - Zone directory on the back wall (which zone is what)
#   - Real racking: white uprights + beams, wooden pallets under every bin
#
# 6 zones x 4 racks x 10 bays x 5 levels = 1200 pallet bins.
# Every bin is an FK_BIN component instance named  A-R01-B01-L1
#   (zone - rack - bay - level). That name is the Bin_ID used by 3DBI.
# Do NOT rename or move bins after building.
#
# Run: Window > Ruby Console, paste this whole file, press Enter.
# Undo: Ctrl+Z (the whole build is a single undo step).

module FlipkartWarehouse
  # ---------------- SETTINGS (metres) ----------------
  # code, zone name, colour
  ZONES = [
    ["A", "Mobiles",         [ 70, 140, 255]],
    ["B", "Electronics",     [  0, 190, 220]],
    ["C", "Fashion",         [200,  90, 220]],
    ["D", "Home & Kitchen",  [ 40, 200, 140]],
    ["E", "Grocery",         [240, 190,  40]],
    ["F", "Beauty",          [250, 110, 160]]
  ]
  RACKS_PER_ZONE = 4
  BAYS_PER_RACK  = 10
  LEVELS         = 5

  BIN_W      = 1.1    # along X (one bay)
  BIN_D      = 1.2    # along Y
  BIN_H      = 1.1    # carton height (pallet + carton must stay below LEVEL_STEP)
  PALLET_H   = 0.14
  BEAM_H     = 0.14
  BAY_PITCH  = 1.3    # centre-to-centre along X
  RACK_PITCH = 3.5    # centre-to-centre along Y (includes the aisle)
  LEVEL_STEP = 1.5
  BASE_Z     = 0.15   # height of level-1 beam above the floor

  ZONE_COLS  = 3      # zones laid out 3 across, 2 down
  ZONE_GAP_X = 5.0
  ZONE_GAP_Y = 7.0    # room for banners + floor names between zone rows

  PAD_FRONT  = 6.0    # floor margin in front (entrance side, y negative)
  PAD_SIDE   = 4.0
  PAD_RIGHT  = 7.0    # dock side: staging space between racks and dock doors
  PAD_BACK   = 3.0
  WALL_T     = 0.3
  WALL_H     = 11.0
  DOOR_W     = 8.0    # entrance gap in the front wall
  DOOR_H     = 5.0

  # --- loading docks (right-hand wall) ---
  DOCKS      = 8
  DOCK_W     = 3.0    # door opening width
  DOCK_H     = 3.8    # door opening height
  DOCK_PITCH = 4.5    # centre-to-centre along Y
  TRAILER_L  = 12.0
  YARD_LEN   = 24.0   # paved yard depth outside the dock wall
  YARD_COLOR = [95, 100, 140]
  FLOOR_COLOR = [10, 25, 80]       # navy
  WALL_COLOR  = [200, 205, 215]
  WALL_ALPHA  = 0.35               # 1.0 = solid walls
  # ---------------------------------------------------

  # ---------- helpers ----------
  def self.get_material(model, name, rgb, alpha = 1.0)
    m = model.materials[name] || model.materials.add(name)
    m.color = Sketchup::Color.new(rgb[0], rgb[1], rgb[2])
    m.alpha = alpha
    m
  end

  # Solid box inside a group. Coordinates in metres.
  def self.box(ents, x, y, z, w, d, h, mat, name = nil)
    g = ents.add_group
    f = g.entities.add_face([x.m, y.m, z.m], [(x + w).m, y.m, z.m],
                            [(x + w).m, (y + d).m, z.m], [x.m, (y + d).m, z.m])
    f.reverse! if f.normal.z < 0
    f.pushpull(h.m)
    g.material = mat
    g.name = name if name
    g
  end

  # Flat rectangle (floor patch) as its own group.
  def self.flat_rect(ents, x0, y0, x1, y1, z, mat, name)
    g = ents.add_group
    f = g.entities.add_face([x0.m, y0.m, z.m], [x1.m, y0.m, z.m],
                            [x1.m, y1.m, z.m], [x0.m, y1.m, z.m])
    f.reverse! if f.normal.z < 0
    f.material = mat
    f.back_material = mat
    g.name = name
    g
  end

  # 3D text centred on `center` (metres). mode :floor lies flat,
  # mode :wall stands upright facing -Y (readable from the front).
  def self.add_text(ents, str, cx, cy, cz, height, mat, mode, extrude = 0.03, name = nil)
    g = ents.add_group
    g.entities.add_3d_text(str, TextAlignLeft, "Arial", true, false,
                           height.m, 0.0, 0, true, extrude.m)
    g.name = name if name
    if mode == :wall || mode == :wall_east
      g.transform!(Geom::Transformation.rotation(ORIGIN, X_AXIS, 90.degrees))
    end
    if mode == :wall_east   # faces +X (readable from the dock yard)
      g.transform!(Geom::Transformation.rotation(ORIGIN, Z_AXIS, 90.degrees))
    end
    g.material = mat
    c = g.bounds.center
    target = Geom::Point3d.new(cx.m, cy.m, cz.m)
    g.transform!(Geom::Transformation.translation(target - c))
    g
  end

  # ---------- shared component definitions ----------
  def self.bin_definition(model)
    defn = model.definitions["FK_BIN"] || model.definitions.add("FK_BIN")
    defn.entities.clear!
    base = defn.entities.add_face([0, 0, 0], [BIN_W.m, 0, 0],
                                  [BIN_W.m, BIN_D.m, 0], [0, BIN_D.m, 0])
    base.reverse! if base.normal.z < 0
    base.pushpull(BIN_H.m)
    defn
  end

  def self.pallet_definition(model)
    defn = model.definitions["FK_PALLET"] || model.definitions.add("FK_PALLET")
    defn.entities.clear!
    wood = get_material(model, "FK_Wood", [170, 120, 60])
    rh = PALLET_H - 0.03
    [0.0, (BIN_W - 0.1) / 2.0, BIN_W - 0.1].each do |rx|
      box(defn.entities, rx, 0, 0, 0.1, BIN_D, rh, wood)
    end
    box(defn.entities, 0, 0, rh, BIN_W, BIN_D, 0.03, wood)
    defn
  end

  def self.upright_definition(model, mat)
    defn = model.definitions["FK_UPRIGHT"] || model.definitions.add("FK_UPRIGHT")
    defn.entities.clear!
    box(defn.entities, 0, 0, 0, 0.1, BIN_D + 0.2, LEVELS * LEVEL_STEP + 0.1, mat)
    defn
  end

  def self.beam_definition(model, mat, length)
    defn = model.definitions["FK_BEAM"] || model.definitions.add("FK_BEAM")
    defn.entities.clear!
    box(defn.entities, 0, 0, 0, length, 0.08, BEAM_H, mat)
    defn
  end

  # Truck: cab + trailer, rear of trailer faces the wall at x = bx.
  def self.add_truck(ents, bx, yc, trailer_mat, cab_mat, name)
    tg = ents.add_group
    tg.name = name
    te = tg.entities
    dark  = get_material(tg.model, "FK_Truck_Dark", [30, 32, 40])
    glass = get_material(tg.model, "FK_Truck_Glass", [40, 70, 120])
    box(te, bx, yc - 1.15, 0.75, TRAILER_L, 2.3, 0.2, dark, "chassis")
    box(te, bx, yc - 1.25, 0.95, TRAILER_L, 2.5, 2.7, trailer_mat, "trailer")
    box(te, bx + TRAILER_L + 0.3, yc - 1.2, 0.75, 2.3, 2.4, 2.4, cab_mat, "cab")
    box(te, bx + TRAILER_L + 2.6, yc - 1.0, 1.7, 0.04, 2.0, 0.7, glass, "windshield")
    [bx + 8.0, bx + 9.3, bx + TRAILER_L + 1.4].each do |wx|
      [yc - 1.2, yc + 0.9].each do |wy|
        wg = te.add_group
        wg.name = "wheel"
        c = wg.entities.add_circle([wx.m, wy.m, 0.5.m], Y_AXIS, 0.5.m, 16)
        f = wg.entities.add_face(c)
        f.pushpull(0.3.m)
        wg.material = dark
      end
    end
    tg
  end

  # ---------- main build ----------
  def self.build
    model = Sketchup.active_model
    ents  = model.active_entities

    zone_w = (BAYS_PER_RACK - 1) * BAY_PITCH + BIN_W
    zone_d = (RACKS_PER_ZONE - 1) * RACK_PITCH + BIN_D
    zone_rows = (ZONES.length / ZONE_COLS.to_f).ceil
    total_w = ZONE_COLS * zone_w + (ZONE_COLS - 1) * ZONE_GAP_X
    total_d = zone_rows * zone_d + (zone_rows - 1) * ZONE_GAP_Y

    x0 = -PAD_SIDE
    x1 = total_w + PAD_RIGHT
    y0 = -PAD_FRONT
    y1 = total_d + PAD_BACK
    cx = (x0 + x1) / 2.0

    model.start_operation("Flipkart Warehouse Builder v2", true)
    begin
      floor_mat = get_material(model, "FK_Floor", FLOOR_COLOR)
      wall_mat  = get_material(model, "FK_Wall", WALL_COLOR, WALL_ALPHA)
      white     = get_material(model, "FK_Frame_White", [235, 238, 242])
      sign_dark = get_material(model, "FK_Sign_Dark", [20, 30, 100])
      text_white = get_material(model, "FK_Text_White", [255, 255, 255])
      text_yellow = get_material(model, "FK_Text_Yellow", [255, 220, 40])

      # ---- floor ----
      flat_rect(ents, x0, y0, x1, y1, 0, floor_mat, "FK_Floor")

      # ---- walls ----
      wg = ents.add_group
      wg.name = "Walls"
      we = wg.entities
      t = WALL_T
      # front wall with entrance gap + lintel
      box(we, x0 - t, y0 - t, 0, (cx - DOOR_W / 2.0) - (x0 - t), t, WALL_H, wall_mat, "Wall front L")
      box(we, cx + DOOR_W / 2.0, y0 - t, 0, (x1 + t) - (cx + DOOR_W / 2.0), t, WALL_H, wall_mat, "Wall front R")
      box(we, cx - DOOR_W / 2.0, y0 - t, DOOR_H, DOOR_W, t, WALL_H - DOOR_H, wall_mat, "Wall front lintel")
      # back + sides
      box(we, x0 - t, y1, 0, (x1 - x0) + 2 * t, t, WALL_H, wall_mat, "Wall back")
      box(we, x0 - t, y0, 0, t, y1 - y0, WALL_H, wall_mat, "Wall left")
      dock_y0 = y0 + ((y1 - y0) - ((DOCKS - 1) * DOCK_PITCH + DOCK_W)) / 2.0
      cur = y0
      (0...DOCKS).each do |i|
        dy = dock_y0 + i * DOCK_PITCH
        box(we, x1, cur, 0, t, dy - cur, WALL_H, wall_mat, "Wall right seg #{i + 1}") if dy > cur
        box(we, x1, dy, DOCK_H, t, DOCK_W, WALL_H - DOCK_H, wall_mat, "Wall right lintel #{i + 1}")
        cur = dy + DOCK_W
      end
      box(we, x1, cur, 0, t, y1 - cur, WALL_H, wall_mat, "Wall right seg end")

      # ---- wall signs ----
      # front wall, outside
      box(ents, cx - 12, y0 - t - 0.15, 7.0, 24, 0.15, 2.6, sign_dark, "Sign board FRONT")
      add_text(ents, "FLIPKART FULFILMENT CENTRE", cx, y0 - t - 0.2, 8.3, 1.3,
               text_yellow, :wall, 0.05, "Sign text FRONT")
      add_text(ents, "ENTRANCE", cx, y0 - t - 0.1, DOOR_H + 0.9, 0.7,
               text_white, :wall, 0.04, "Sign text ENTRANCE")

      # back wall, inside: zone directory (same grid as the floor plan)
      box(ents, x0 + 1, y1 - 0.15, 4.6, (x1 - x0) - 2, 0.15, 5.6, sign_dark, "Directory board")
      add_text(ents, "ZONE DIRECTORY", cx, y1 - 0.2, 9.3, 0.9,
               text_yellow, :wall, 0.04, "Directory title")

      # ---- loading docks + trucks + yard ----
      dock_layer = model.layers.add("Docks")
      yard_mat   = get_material(model, "FK_Yard", YARD_COLOR)
      door_mat   = get_material(model, "FK_DockDoor", [70, 75, 90])
      lev_mat    = get_material(model, "FK_Leveller", [255, 200, 0])
      trailers   = [get_material(model, "FK_Trailer_Grey", [125, 130, 140]),
                    get_material(model, "FK_Trailer_White", [235, 237, 242])]
      cab_mat    = get_material(model, "FK_Cab", [250, 250, 252])

      yard = flat_rect(ents, x1 + t, y0 - t, x1 + t + YARD_LEN, y1 + t, 0, yard_mat, "Truck yard")
      yard.layer = dock_layer

      (0...DOCKS).each do |i|
        n  = i + 1
        dy = dock_y0 + i * DOCK_PITCH
        yc = dy + DOCK_W / 2.0
        parts = []
        parts << box(ents, x1 + 0.1, dy, 2.6, 0.1, DOCK_W, DOCK_H - 2.6, door_mat, "Dock #{n} door")
        parts << box(ents, x1 - 1.5, dy + 0.1, 0, 1.5, DOCK_W - 0.2, 0.08, lev_mat, "Dock #{n} leveller")
        parts << box(ents, x1 + t, dy - 0.2, DOCK_H + 0.3, 0.1, DOCK_W + 0.4, 0.9, sign_dark, "Dock #{n} sign board")
        parts << add_text(ents, "DOCK #{n}", x1 + t + 0.13, yc, DOCK_H + 0.75, 0.55,
                          text_yellow, :wall_east, 0.03, "Dock #{n} sign text")
        parts << add_text(ents, "DOCK #{n}", x1 - 2.2, yc, 0.04, 0.8,
                          text_yellow, :floor, 0.02, "Dock #{n} floor number")
        parts << add_truck(ents, x1 + t + 0.4, yc, trailers[i % 2], cab_mat, "TRUCK DOCK #{n}")
        parts.each { |e| e.layer = dock_layer }
      end

      # ---- shared definitions ----
      defn_bin    = bin_definition(model)
      defn_pallet = pallet_definition(model)
      rack_len    = zone_w + 0.3
      defn_up     = upright_definition(model, white)
      defn_beam   = beam_definition(model, white, rack_len)

      count = 0
      ZONES.each_with_index do |(code, zname, rgb), zi|
        col = zi % ZONE_COLS
        row = zi / ZONE_COLS
        zx = col * (zone_w + ZONE_GAP_X)
        zy = row * (zone_d + ZONE_GAP_Y)
        zcx = zx + zone_w / 2.0
        mat   = get_material(model, "FK_Zone_#{code}", rgb)
        layer = model.layers.add("Zone #{code}")
        label = "ZONE #{code} - #{zname.upcase}"

        # --- zone floor patch ---
        patch = flat_rect(ents, zx - 0.6, zy - 1.0, zx + zone_w + 0.6, zy + zone_d + 0.6,
                          0.02, mat, "Zone #{code} floor")
        patch.layer = layer

        # --- floor name in front of the zone ---
        ft = add_text(ents, label, zcx, zy - 2.6, 0.04, 0.9, text_white, :floor, 0.02,
                      "Zone #{code} floor name")
        ft.layer = layer

        # --- overhead banner on two posts ---
        by = zy - 1.4
        p1 = box(ents, zx - 0.3, by - 0.05, 0, 0.15, 0.15, 9.8, white, "Zone #{code} post L")
        p2 = box(ents, zx + zone_w + 0.15, by - 0.05, 0, 0.15, 0.15, 9.8, white, "Zone #{code} post R")
        bn = box(ents, zx - 0.3, by - 0.1, 8.3, zone_w + 0.75, 0.12, 1.5, mat, "Zone #{code} banner")
        bt = add_text(ents, label, zcx, by - 0.14, 9.05, 0.75, text_white, :wall, 0.03,
                      "Zone #{code} banner text")
        [p1, p2, bn, bt].each { |e| e.layer = layer }

        # --- zone line on the back-wall directory ---
        dz = (row == 0) ? 8.0 : 6.3
        dx = (zcx)
        dt = add_text(ents, label, dx, y1 - 0.2, dz, 0.7, text_white, :wall, 0.03,
                      "Directory #{code}")
        dt.layer = layer
        dchip = box(ents, dx - zone_w / 2.0 + 0.3, y1 - 0.18, dz - 0.6, 0.35, 0.03, 1.2, mat,
                    "Directory chip #{code}")
        dchip.layer = layer

        # --- racks ---
        (1..RACKS_PER_ZONE).each do |r|
          ry = zy + (r - 1) * RACK_PITCH

          # frame (uprights + beams) in one group per rack
          fg = ents.add_group
          fg.name  = format("FRAME %s-R%02d", code, r)
          fg.layer = layer
          fe = fg.entities
          (0..BAYS_PER_RACK).each do |u|
            ux = zx - 0.15 + u * BAY_PITCH
            fe.add_instance(defn_up, Geom::Transformation.new([ux.m, (ry - 0.1).m, 0]))
          end
          (1..LEVELS).each do |l|
            bz = BASE_Z + (l - 1) * LEVEL_STEP
            fe.add_instance(defn_beam, Geom::Transformation.new([(zx - 0.15).m, (ry - 0.08).m, bz.m]))
            fe.add_instance(defn_beam, Geom::Transformation.new([(zx - 0.15).m, (ry + BIN_D).m, bz.m]))
          end

          (1..BAYS_PER_RACK).each do |b|
            (1..LEVELS).each do |l|
              x = zx + (b - 1) * BAY_PITCH
              bz = BASE_Z + (l - 1) * LEVEL_STEP + BEAM_H   # pallet sits on the beams

              pal = ents.add_instance(defn_pallet, Geom::Transformation.new([x.m, ry.m, bz.m]))
              pal.layer = layer

              inst = ents.add_instance(defn_bin,
                       Geom::Transformation.new([x.m, ry.m, (bz + PALLET_H).m]))
              bin_id = format("%s-R%02d-B%02d-L%d", code, r, b, l)
              inst.name     = bin_id
              inst.material = mat
              inst.layer    = layer
              inst.set_attribute("FK", "Bin_ID", bin_id)
              inst.set_attribute("FK", "Zone", zname)
              count += 1
            end
          end
        end
      end

      model.commit_operation
      puts "Done: #{count} bins created in #{ZONES.length} named zones, #{DOCKS} docks built"
      puts "Warehouse footprint: #{(x1 - x0).round(1)} m x #{(y1 - y0).round(1)} m"
    rescue => e
      model.abort_operation
      puts "Build failed: #{e.message}"
      puts e.backtrace.first(5)
    end
  end
end

FlipkartWarehouse.build
