require 'haml'
require 'json'

get '/drop/?' do
  haml :'drop/index', :locals => {
    :title_append => " # 掉落统计"
  }
end

get '/drop/map/:name.?:format?' do
  map_id = nil
  KCConstants.maps.each do |id, name|
    map_id = id if name == params[:name]
  end

  halt 404 if map_id.nil?

  params[:format] ||= 'html'
  if params[:format] == 'html'
    return haml :'drop/map/query', :locals => {
      :location => 'drop',
      :query_by => 'map',
      :title_append => " # 掉落统计 - #{KCConstants.maps[map_id]}",
      :map_id => map_id,
    }
  end

  halt 404 unless params[:format] == 'json'

  enemy_hash = {}
  DropShipRecord.where(mapId: map_id).distinct(:cellId).sort.each do |cell_id|
    enemy_hash[KCConstants.cells[map_id][cell_id]] ||= []
    enemy_hash[KCConstants.cells[map_id][cell_id]].push cell_id
  end

  map = %Q{
    function() {
      emit(this.shipId, {
        rank: this.rank,
        teitokuLv: this.teitokuLv,
        mapLv: this.mapLv,
        enemy: this.enemyShips.join('/') + '/' + this.enemyFormation,
        reduced: false
      });
    }
  }

  reduce = %Q{
    function(key, values) {
      var reduced = {
        s: 0,
        a: 0,
        b: 0,
        c: 0,
        d: 0,
        e: 0,
        hqLv: [151, 0],
        mapLv: [0, 0, 0, 0],
        enemy: {},
        reduced: true
      };

      values.forEach(function(value) {
        switch(value.rank) {
          case 'S':
            reduced.s++;
            break;
          case 'A':
            reduced.a++;
            break;
          case 'B':
            reduced.b++;
            break;
          case 'C':
            reduced.c++;
            break;
          case 'D':
            reduced.d++;
            break;
          case 'E':
            reduced.e++;
            break;
        }

        if (value.teitokuLv < reduced.hqLv[0]) {
          reduced.hqLv[0] = value.teitokuLv;
        }
        if (value.teitokuLv > reduced.hqLv[1]) {
          reduced.hqLv[1] = value.teitokuLv;
        }

        reduced.mapLv[value.mapLv]++;

        reduced.enemy[value.enemy] = reduced.enemy[value.enemy] || 0;
        reduced.enemy[value.enemy]++;
      });

      return reduced;
    }
  }

  finalize = %Q{
    function(key, value) {
      if (!value.reduced) {
        var reduced = {
          s: 0,
          a: 0,
          b: 0,
          c: 0,
          d: 0,
          e: 0,
          hqLv: [value.teitokuLv, value.teitokuLv],
          mapLv: [0, 0, 0, 0],
          enemy: {},
          reduced: true
        };

        switch(value.rank) {
          case 'S':
            reduced.s = 1;
            break;
          case 'A':
            reduced.a = 1;
            break;
          case 'B':
            reduced.b = 1;
            break;
          case 'C':
            reduced.c = 1;
            break;
          case 'D':
            reduced.d = 1;
            break;
          case 'E':
            reduced.e = 1;
            break;
        }
        reduced.mapLv[value.mapLv]++;
        reduced.enemy[value.enemy] = 1;

        return reduced;
      }
      return value;
    }
  }

  # query now

  result = []
  enemy_hash.each do |enemy_name, cell_id_list|
    ship_list = []
    drop_sum = 0
    DropShipRecord.where(:mapId => map_id, :cellId.in => cell_id_list)
      .map_reduce(map, reduce).out(inline: 1)
      .finalize(finalize).each do |q|
        enemies = []
        q['value']['enemy'].each do |k, v|
          idx = k.split('/')
          e = (idx[0..5].map {|i| i == '-1' ? nil : KCConstants.ships[i.to_i]}).compact
          enemies.push({
            enemy: "#{e.join('/')}(#{KCConstants.formations[idx[6].to_i]})",
            count: v.to_i
          })
        end

        count = q['value']['mapLv'].map{|i| i.to_i}.inject(:+)

        ship_list.push({
          name: KCConstants.ships[q['_id'].to_i],
          s: q['value']['s'].to_i,
          a: q['value']['a'].to_i,
          b: q['value']['b'].to_i,
          c: q['value']['c'].to_i,
          d: q['value']['d'].to_i,
          e: q['value']['e'].to_i,
          count: count,
          detail: {
            hqLvRange: q['value']['hqLv'].map {|i| i.to_i},
            mapLvSet: q['value']['mapLv'].map {|i| i.to_i},
            enemySet: enemies
          }
        })

        drop_sum += count
      end
    result.push({ name: enemy_name, ships: ship_list, count: drop_sum })
  end

  content_type :json
  json_obj = { database: 'drop', query: params[:name], result: result }
  json_obj.to_json
end

get '/drop/ship/:name.?:format?' do
  ship_sortno = nil
  KCConstants.ships.each do |id, name|
    ship_sortno = id if name == params[:name]
  end

  halt 404 if ship_sortno.nil?

  params[:format] ||= 'html'
  if params[:format] == 'html'
    return haml :'drop/ship/query'
  end

  halt 404 unless params[:format] == 'json'

  map_id_hash = {}
  DropShipRecord.where(shipId: ship_sortno).distinct(:mapId).sort.each do |map_id|
    map_id_hash[map_id / 10] ||= []
    map_id_hash[map_id / 10].push map_id
  end

  map = %Q{
    function() {
      emit(this.cellId, {
        rank: this.rank,
        teitokuLv: this.teitokuLv,
        mapLv: this.mapLv,
        enemy: this.enemyShips.join('/') + '/' + this.enemyFormation,
        reduced: false
      });
    }
  }

  reduce = %Q{
    function(key, values) {
      var reduced = {
        s: 0,
        a: 0,
        b: 0,
        c: 0,
        d: 0,
        e: 0,
        hqLv: [151, 0],
        mapLv: [0, 0, 0, 0],
        enemy: {},
        reduced: true
      };

      values.forEach(function(value) {
        switch(value.rank) {
          case 'S':
            reduced.s++;
            break;
          case 'A':
            reduced.a++;
            break;
          case 'B':
            reduced.b++;
            break;
          case 'C':
            reduced.c++;
            break;
          case 'D':
            reduced.d++;
            break;
          case 'E':
            reduced.e++;
            break;
        }

        if (value.teitokuLv < reduced.hqLv[0]) {
          reduced.hqLv[0] = value.teitokuLv;
        }
        if (value.teitokuLv > reduced.hqLv[1]) {
          reduced.hqLv[1] = value.teitokuLv;
        }

        reduced.mapLv[value.mapLv]++;

        reduced.enemy[value.enemy] = reduced.enemy[value.enemy] || 0;
        reduced.enemy[value.enemy]++;
      });

      return reduced;
    }
  }

  finalize = %Q{
    function(key, value) {
      if (!value.reduced) {
        var reduced = {
          s: 0,
          a: 0,
          b: 0,
          c: 0,
          d: 0,
          e: 0,
          hqLv: [value.teitokuLv, value.teitokuLv],
          mapLv: [0, 0, 0, 0],
          enemy: {},
          reduced: true
        };

        switch(value.rank) {
          case 'S':
            reduced.s = 1;
            break;
          case 'A':
            reduced.a = 1;
            break;
          case 'B':
            reduced.b = 1;
            break;
          case 'C':
            reduced.c = 1;
            break;
          case 'D':
            reduced.d = 1;
            break;
          case 'E':
            reduced.e = 1;
            break;
        }
        reduced.mapLv[value.mapLv]++;
        reduced.enemy[value.enemy] = 1;

        return reduced;
      }
      return value;
    }
  }

  # query now

  result = []
  drop_sum = 0
  map_id_hash.each do |area_id, map_id_list|
    map_list = []
    map_id_list.each do |map_id|
      cell_list = []
      DropShipRecord.where(shipId: ship_sortno, mapId: map_id)
        .map_reduce(map, reduce).out(inline: 1)
        .finalize(finalize).each do |q|
          enemies = []
          q['value']['enemy'].each do |k, v|
            idx = k.split('/')
            e = (idx[0..5].map {|i| i == '-1' ? nil : KCConstants.ships[i.to_i]}).compact
            enemies.push({
              enemy: "#{e.join('/')}(#{KCConstants.formations[idx[6].to_i]})",
              count: v.to_i
            })
          end

          count = q['value']['mapLv'].map{|i| i.to_i}.inject(:+)

          cell_list.push({
            name: KCConstants.cells[map_id][q['_id'].to_i],
            s: q['value']['s'].to_i,
            a: q['value']['a'].to_i,
            b: q['value']['b'].to_i,
            c: q['value']['c'].to_i,
            d: q['value']['d'].to_i,
            e: q['value']['e'].to_i,
            count: count,
            detail: {
              hqLvRange: q['value']['hqLv'].map {|i| i.to_i},
              mapLvSet: q['value']['mapLv'].map {|i| i.to_i},
              enemySet: enemies
            }
          })

          drop_sum += count
        end
      map_list.push({ name: KCConstants.maps[map_id], cells: cell_list })
    end
    result.push({ name: KCConstants.areas[area_id], maps: map_list })
  end

  content_type :json
  json_obj = { database: 'drop', query: params[:name], result: result, count: drop_sum }
  json_obj.to_json
end
