# Things that work for both regularly and irregularly sampled data
function pop_chan_tail!(Ch::SeisChannel)
  ((Ch.gain == 1) || isnan(Ch.gain)) && (Ch.gain = rand()*10^rand(0:10))    # gain
  if isempty(Ch.loc)
    loc = GeoLoc()
    for f in fieldnames(GeoLoc)
      x = rand(Float64)
      if f != :datum
        if f == :lat || f == :inc
          x = 180*(x-0.5)
        elseif f == :lon || f == :az
          x = 360*(x-0.5)
        end
        setfield!(loc, f, x)
      else
        setfield!(loc, f, x > 0.5 ? "WGS-84" : x > 0.25 ? "ETRS89" : x > 0.1 ? "GRS 80" : "JGD2011")
      end
    end
  end                                                                       # loc
  if isempty(Ch.misc)
    pop_rand_dict!(Ch.misc, rand(4:24))                                     # misc
  end
  note!(Ch, "Created by function populate_chan!.")                          # note
end

# Populate a channel with irregularly-sampled (campaign-style) data
function populate_irr!(Ch::SeisChannel; nx::Int64=0)
  irregular_units = ["%", "(% cloud cover)", "(direction vector)", "C", "K", "None", "Pa", "T", "V", "W", "m", "m/m", "m/s", "m/s^2", "m^3/m^3", "rad", "rad/s", "rad/s^2", "tonnes SO2"]

  Ch.fs = 0
  if isempty(Ch.id) || Ch.id == "...YYY"
    chan = "OY"*randstring('A':'Z',1)
    net = ur2()
    sta = uppercase(randstring('A':'Z', rand(1:5)))
    loc = ur2()

    # id
    Ch.id = join([net,sta,loc,chan],'.')

  end

  # units
  if isempty(Ch.units) || units == lowercase("unknown")
    Ch.units = rand(irregular_units)
  end

  if isempty(Ch.x) || isempty(Ch.t)
    ts = round(Int, sμ*(time()-86400+randn()))
    if nx == 0
      L = 2^rand(6:12)
    else
      L = nx
    end
    Ls = rand(1200:7200)
    Ch.x = (rand(L) .- (rand(Bool) == true ? 0.5 :  0.0)).*(10 .^ (rand(1:10, L)))
    Ch.t = hcat(collect(1:1:L), ts.+sort(rand(UnitRange{Int64}(1:Ls), L)))
  end
  Ch.src = string("randSeisChannel(c=true, nx=",  nx, ")")

  pop_chan_tail!(Ch)
  return nothing
end

# Populate a channel with regularly-sampled (time-series) data
function populate_chan!(Ch::SeisChannel; s::Bool=false, nx::Int64=0)
  fc_vals = Float64[1/120 1/60 1/30 0.2 1.0 1.0 1.0 2.0 4.5 15.0]
  fs_vals = Float64[0.1, 1.0, 2.0, 5.0, 10.0, 20.0, 25.0, 40.0, 50.0, 60.0, 62.5,
    80.0, 100.0, 120.0, 125.0, 250.0]
  bcodes = Char['V', 'L', 'M', 'M', 'B', 'S', 'S', 'S', 'S', 'S', 'S', 'H', 'S', 'E', 'E', 'C']

  # Ch.name
  isempty(Ch.name) && (Ch.name = randstring(12))

  # Ch.fs
  (isempty(Ch.fs) || Ch.fs == 0 || isnan(Ch.fs)) && (Ch.fs = rand(fs_vals))

  fc = rand(fc_vals[fc_vals .< Ch.fs/2])

  # An empty ID generates codes and units to match values real data might have
  if isempty(Ch.id) || Ch.id == "...YYY"
    bcode = getbandcode(Ch.fs)
    (icode,ccode,units) = getyp2codes(bcode, s)
    chan = join([bcode, icode, ccode])
    net = ur2()
    sta = uppercase(randstring('A':'Z', rand(1:5)))
    loc = rand() < 0.3 ? "" : ur2()
    Ch.id = join([net,sta,"",chan],'.')                                     # id
    if isempty(Ch.units)
      Ch.units = units                                                      # units
    end
  end

  # Need this even if Ch had an ID value when populate_chan! was called
  cha = split(Ch.id, '.')[4]
  ccode = cha[2]

  # A random instrument response function
  if isempty(Ch.resp)
    T = rand() < 0.5 ? Float32 : Float64
    i = rand(1:4)
    zstub = zeros(T, 2*i)
    pstub = 10 .*rand(T, i)
    if T == Float32
      Ch.resp = PZResp(0.0f0, complex.(zstub), vcat(pstub .+ pstub.*im, pstub .- pstub*im))    # resp
    else
      Ch.resp = PZResp64(0.0, complex.(zstub), vcat(pstub .+ pstub.*im, pstub .- pstub*im))    # resp
    end
  end

  # random noise for data, with random short time gaps; gaussian noise for a
  # time series, uniform noise with a random exponent otherwise
  if isempty(Ch.x) || isempty(Ch.t)                                         # x

    if nx == 0
      # Change: length is always 20-120 minutes
      Ls = rand(1200:7200)
      Lx = ceil(Int, Ls*Ch.fs)
    else
      Lx = nx
    end
    Ch.x = randn(rand() < 0.5 ? Float32 : Float64, Lx)

    ts = time()-86400+randn()                                               # t
    L = rand(0:9)
    t = zeros(2+L, 2)

    # first row is always start time
    t[1,:] = [1 round(Int64, ts/μs)]

    # rest are random time gaps
    gaps = unique(rand(2:Lx, L, 1))
    while length(unique(gaps)) < L
      gaps = unique(rand(2:Lx, L, 1))
    end
    t[2:L+1,1] = gaps
    for i = 2:L+1
      t[i,2] = round(Int64, (rand(1:100)+rand())*sμ)
    end

    # control for gap in last sample
    if any(t[:,1].==length(Ch.x)) == true
      t = t[1:L+1,:]
    else
      t[L+2,:] = [Lx 0]
    end
    Ch.t = sortslices(t, dims=1)
  end

  Ch.src = string("randSeisChannel(c=false, nx=",  nx, ")")
  pop_chan_tail!(Ch)
  return nothing
end

"""
    randSeisChannel()

Generate a random channel of geophysical time-series data as a SeisChannel.

    randSeisChannel(c=true)

Generate a random channel of irregularly-sampled data.

    randSeisChannel(s=true)

Generate a random channel of regularly-sampled seismic data.
"""
function randSeisChannel(; c::Bool=false, s::Bool=false, nx::Int64=0)
  Ch = SeisChannel()
  if c == true
    populate_irr!(Ch, nx=nx)
  else
    populate_chan!(Ch, s=s, nx=nx)
  end
  return Ch
end
