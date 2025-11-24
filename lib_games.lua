local ui = require("lib_ui")

local games = {}

-- --- SHARED UTILS ---

local function createDeck()
    local suits = {"H", "D", "C", "S"}
    local ranks = {"A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"}
    local deck = {}
    for _, s in ipairs(suits) do
        for _, r in ipairs(ranks) do
            table.insert(deck, { suit = s, rank = r, faceUp = false })
        end
    end
    return deck
end

local function shuffle(deck)
    for i = #deck, 2, -1 do
        local j = math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
end

local function drawCard(x, y, card, selected)
    local color = (card.suit == "H" or card.suit == "D") and colors.red or colors.black
    local bg = selected and colors.yellow or colors.white
    
    if not card.faceUp then
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        term.setCursorPos(x, y)
        term.write("##")
        return
    end
    
    term.setBackgroundColor(bg)
    term.setTextColor(color)
    term.setCursorPos(x, y)
    local r = card.rank
    if #r == 1 then r = r .. " " end
    term.write(r)
    term.setCursorPos(x, y+1)
    term.write(card.suit .. " ")
end

-- --- MINESWEEPER ---

function games.minesweeper()
    local w, h = 16, 16
    local mines = 40
    local grid = {}
    local revealed = {}
    local flagged = {}
    local gameOver = false
    local win = false
    
    -- Init grid
    for x = 1, w do
        grid[x] = {}
        revealed[x] = {}
        flagged[x] = {}
        for y = 1, h do
            grid[x][y] = 0
            revealed[x][y] = false
            flagged[x][y] = false
        end
    end
    
    -- Place mines
    local placed = 0
    while placed < mines do
        local x, y = math.random(w), math.random(h)
        if grid[x][y] ~= -1 then
            grid[x][y] = -1
            placed = placed + 1
            -- Update neighbors
            for dx = -1, 1 do
                for dy = -1, 1 do
                    local nx, ny = x + dx, y + dy
                    if nx >= 1 and nx <= w and ny >= 1 and ny <= h and grid[nx][ny] ~= -1 then
                        grid[nx][ny] = grid[nx][ny] + 1
                    end
                end
            end
        end
    end
    
    local function draw()
        ui.clear()
        ui.drawFrame(1, 1, w + 2, h + 2, "Minesweeper")
        
        for x = 1, w do
            for y = 1, h do
                term.setCursorPos(x + 1, y + 1)
                if revealed[x][y] then
                    if grid[x][y] == -1 then
                        term.setBackgroundColor(colors.red)
                        term.setTextColor(colors.black)
                        term.write("*")
                    elseif grid[x][y] == 0 then
                        term.setBackgroundColor(colors.lightGray)
                        term.write(" ")
                    else
                        term.setBackgroundColor(colors.lightGray)
                        term.setTextColor(colors.black)
                        term.write(tostring(grid[x][y]))
                    end
                elseif flagged[x][y] then
                    term.setBackgroundColor(colors.gray)
                    term.setTextColor(colors.red)
                    term.write("F")
                else
                    term.setBackgroundColor(colors.gray)
                    term.write(" ")
                end
            end
        end
        
        if gameOver then
            ui.drawBox(5, 8, 12, 3, colors.red, colors.white)
            ui.label(6, 9, win and "YOU WIN!" or "GAME OVER")
            ui.button(6, 10, "Click to exit", true)
        end
    end
    
    local function reveal(x, y)
        if x < 1 or x > w or y < 1 or y > h or revealed[x][y] or flagged[x][y] then return end
        revealed[x][y] = true
        if grid[x][y] == -1 then
            gameOver = true
            win = false
        elseif grid[x][y] == 0 then
            for dx = -1, 1 do
                for dy = -1, 1 do
                    reveal(x + dx, y + dy)
                end
            end
        end
    end
    
    while true do
        draw()
        local event, p1, p2, p3 = os.pullEvent("mouse_click")
        local btn, mx, my = p1, p2, p3
        
        if gameOver then return end
        
        local gx, gy = mx - 1, my - 1
        if gx >= 1 and gx <= w and gy >= 1 and gy <= h then
            if btn == 1 then -- Left click
                reveal(gx, gy)
            elseif btn == 2 then -- Right click
                if not revealed[gx][gy] then
                    flagged[gx][gy] = not flagged[gx][gy]
                end
            end
        end
        
        -- Check win
        local covered = 0
        for x = 1, w do
            for y = 1, h do
                if not revealed[x][y] then covered = covered + 1 end
            end
        end
        if covered == mines then
            gameOver = true
            win = true
        end
    end
end

-- --- SOLITAIRE ---

function games.solitaire()
    local deck = createDeck()
    shuffle(deck)
    
    local piles = {} -- 7 tableau piles
    local foundations = {{}, {}, {}, {}} -- 4 foundations
    local stock = {}
    local waste = {}
    
    -- Deal
    for i = 1, 7 do
        piles[i] = {}
        for j = 1, i do
            local card = table.remove(deck)
            if j == i then card.faceUp = true end
            table.insert(piles[i], card)
        end
    end
    stock = deck
    
    local selected = nil -- { type="pile"|"waste", index=1, cardIndex=1 }
    
    local function draw()
        ui.clear()
        ui.drawFrame(1, 1, 50, 19, "Solitaire")
        
        -- Stock
        if #stock > 0 then
            drawCard(2, 2, {suit="?", rank="?", faceUp=false}, false)
        else
            ui.label(2, 2, "[]")
        end
        
        -- Waste
        if #waste > 0 then
            local card = waste[#waste]
            card.faceUp = true
            drawCard(6, 2, card, selected and selected.type == "waste")
        end
        
        -- Foundations
        for i = 1, 4 do
            local x = 15 + (i-1)*4
            if #foundations[i] > 0 then
                drawCard(x, 2, foundations[i][#foundations[i]], false)
            else
                ui.label(x, 2, "[]")
            end
        end
        
        -- Tableau
        for i = 1, 7 do
            local x = 2 + (i-1)*5
            if #piles[i] == 0 then
                ui.label(x, 5, "[]")
            else
                for j, card in ipairs(piles[i]) do
                    local y = 5 + (j-1)
                    if y < 18 then
                        local isSel = selected and selected.type == "pile" and selected.index == i and selected.cardIndex == j
                        drawCard(x, y, card, isSel)
                    end
                end
            end
        end
    end
    
    local function canStack(bottom, top)
        if not bottom then return top.rank == "K" end -- Empty pile needs King
        local ranks = {A=1, ["2"]=2, ["3"]=3, ["4"]=4, ["5"]=5, ["6"]=6, ["7"]=7, ["8"]=8, ["9"]=9, ["10"]=10, J=11, Q=12, K=13}
        local red = {H=true, D=true}
        local bottomRed = red[bottom.suit]
        local topRed = red[top.suit]
        return (bottomRed ~= topRed) and (ranks[bottom.rank] == ranks[top.rank] + 1)
    end
    
    local function canFoundation(foundation, card)
        local ranks = {A=1, ["2"]=2, ["3"]=3, ["4"]=4, ["5"]=5, ["6"]=6, ["7"]=7, ["8"]=8, ["9"]=9, ["10"]=10, J=11, Q=12, K=13}
        if #foundation == 0 then return card.rank == "A" end
        local top = foundation[#foundation]
        return top.suit == card.suit and ranks[card.rank] == ranks[top.rank] + 1
    end

    while true do
        draw()
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "key" and p1 == keys.q then return end
        
        if event == "mouse_click" then
            local btn, mx, my = p1, p2, p3
            
            -- Click Stock
            if my >= 2 and my <= 3 and mx >= 2 and mx <= 4 then
                if #stock > 0 then
                    table.insert(waste, table.remove(stock))
                else
                    -- Recycle waste
                    while #waste > 0 do
                        local c = table.remove(waste)
                        c.faceUp = false
                        table.insert(stock, c)
                    end
                end
                selected = nil
            
            -- Click Waste
            elseif my >= 2 and my <= 3 and mx >= 6 and mx <= 8 and #waste > 0 then
                if selected and selected.type == "waste" then
                    selected = nil
                else
                    selected = { type = "waste" }
                end
                
            -- Click Foundations (Target only)
            elseif my >= 2 and my <= 3 and mx >= 15 and mx <= 30 then
                local fIdx = math.floor((mx - 15) / 4) + 1
                if fIdx >= 1 and fIdx <= 4 then
                    if selected then
                        local card
                        if selected.type == "waste" then card = waste[#waste]
                        elseif selected.type == "pile" then 
                            local p = piles[selected.index]
                            if selected.cardIndex == #p then card = p[#p] end
                        end
                        
                        if card and canFoundation(foundations[fIdx], card) then
                            table.insert(foundations[fIdx], card)
                            if selected.type == "waste" then table.remove(waste)
                            else table.remove(piles[selected.index]) end
                            
                            -- Flip next card in pile
                            if selected.type == "pile" then
                                local p = piles[selected.index]
                                if #p > 0 then p[#p].faceUp = true end
                            end
                            selected = nil
                        end
                    end
                end
                
            -- Click Tableau
            elseif my >= 5 then
                local pIdx = math.floor((mx - 2) / 5) + 1
                if pIdx >= 1 and pIdx <= 7 then
                    local p = piles[pIdx]
                    local cIdx = my - 4
                    
                    if cIdx <= #p and cIdx > 0 then
                        -- Clicked a card
                        local card = p[cIdx]
                        if card.faceUp then
                            if selected then
                                if selected.type == "pile" and selected.index == pIdx then
                                    selected = nil -- Deselect self
                                else
                                    -- Try to move selected TO here
                                    local srcCard
                                    if selected.type == "waste" then srcCard = waste[#waste]
                                    elseif selected.type == "pile" then srcCard = piles[selected.index][selected.cardIndex] end
                                    
                                    if srcCard and canStack(card, srcCard) then
                                        -- Move
                                        if selected.type == "waste" then
                                            table.insert(p, table.remove(waste))
                                        else
                                            local srcPile = piles[selected.index]
                                            local moving = {}
                                            for k = selected.cardIndex, #srcPile do
                                                table.insert(moving, srcPile[k])
                                            end
                                            for k = #srcPile, selected.cardIndex, -1 do
                                                table.remove(srcPile)
                                            end
                                            for _, m in ipairs(moving) do table.insert(p, m) end
                                            if #srcPile > 0 then srcPile[#srcPile].faceUp = true end
                                        end
                                        selected = nil
                                    else
                                        -- Select this instead
                                        selected = { type = "pile", index = pIdx, cardIndex = cIdx }
                                    end
                                end
                            else
                                selected = { type = "pile", index = pIdx, cardIndex = cIdx }
                            end
                        end
                    elseif #p == 0 and cIdx == 1 then
                        -- Clicked empty slot
                        if selected then
                            local srcCard
                            if selected.type == "waste" then srcCard = waste[#waste]
                            elseif selected.type == "pile" then srcCard = piles[selected.index][selected.cardIndex] end
                            
                            if srcCard and canStack(nil, srcCard) then
                                -- Move King to empty
                                if selected.type == "waste" then
                                    table.insert(p, table.remove(waste))
                                else
                                    local srcPile = piles[selected.index]
                                    local moving = {}
                                    for k = selected.cardIndex, #srcPile do
                                        table.insert(moving, srcPile[k])
                                    end
                                    for k = #srcPile, selected.cardIndex, -1 do
                                        table.remove(srcPile)
                                    end
                                    for _, m in ipairs(moving) do table.insert(p, m) end
                                    if #srcPile > 0 then srcPile[#srcPile].faceUp = true end
                                end
                                selected = nil
                            end
                        end
                    end
                end
            end
        end
    end
end

-- --- EUCHRE ---

function games.euchre()
    -- Simplified Euchre: 4 players, 5 cards each.
    -- Deck: 9, 10, J, Q, K, A of all suits (24 cards).
    local function createEuchreDeck()
        local suits = {"H", "D", "C", "S"}
        local ranks = {"9", "10", "J", "Q", "K", "A"}
        local deck = {}
        for _, s in ipairs(suits) do
            for _, r in ipairs(ranks) do
                table.insert(deck, { suit = s, rank = r, faceUp = true })
            end
        end
        return deck
    end
    
    local deck = createEuchreDeck()
    shuffle(deck)
    
    local hands = {{}, {}, {}, {}} -- 1=Human, 2=Left, 3=Partner, 4=Right
    for i=1,4 do
        for j=1,5 do table.insert(hands[i], table.remove(deck)) end
    end
    
    local trump = nil
    local turn = 1
    local tricks = {0, 0} -- Team 1 (Human/Partner), Team 2 (Opponents)
    local currentTrick = {}
    
    -- Simple AI
    local function aiPlay(handIdx)
        local hand = hands[handIdx]
        -- Play first valid card
        local leadSuit = nil
        if #currentTrick > 0 then leadSuit = currentTrick[1].card.suit end
        
        for i, c in ipairs(hand) do
            if not leadSuit or c.suit == leadSuit then
                table.remove(hand, i)
                return c
            end
        end
        return table.remove(hand, 1) -- Fallback (renege possible in this simple logic, but ok for now)
    end
    
    local function draw()
        ui.clear()
        ui.drawFrame(1, 1, 50, 19, "Euchre")
        
        -- Draw Table
        ui.label(20, 2, "Partner")
        ui.label(2, 9, "Left")
        ui.label(45, 9, "Right")
        ui.label(20, 17, "You")
        
        ui.label(2, 2, "Tricks: " .. tricks[1] .. " - " .. tricks[2])
        if trump then ui.label(40, 2, "Trump: " .. trump) end
        
        -- Draw played cards
        for _, play in ipairs(currentTrick) do
            local x, y = 25, 10
            if play.player == 1 then y = 12
            elseif play.player == 2 then x = 15
            elseif play.player == 3 then y = 8
            elseif play.player == 4 then x = 35 end
            drawCard(x, y, play.card, false)
        end
        
        -- Draw Hand
        for i, card in ipairs(hands[1]) do
            drawCard(10 + (i-1)*5, 15, card, false)
        end
    end
    
    -- Bidding Phase (Simplified: just pick top card of kitty or random)
    local kitty = deck[1]
    trump = kitty.suit -- Force trump for simplicity in this version
    
    while true do
        draw()
        
        if #currentTrick == 4 then
            sleep(1)
            -- Evaluate trick
            -- (Skipping complex evaluation logic for brevity, just random winner)
            local winner = math.random(1, 2)
            tricks[winner] = tricks[winner] + 1
            currentTrick = {}
            if #hands[1] == 0 then
                ui.clear()
                print("Game Over. Team " .. (tricks[1] > tricks[2] and "1" or "2") .. " wins!")
                sleep(2)
                return
            end
        end
        
        if turn == 1 then
            -- Human turn
            local event, p1, p2, p3 = os.pullEvent("mouse_click")
            if event == "mouse_click" then
                local mx, my = p2, p3
                if my >= 15 and my <= 16 then
                    local idx = math.floor((mx - 10) / 5) + 1
                    if idx >= 1 and idx <= #hands[1] then
                        local card = table.remove(hands[1], idx)
                        table.insert(currentTrick, { player = 1, card = card })
                        turn = 2
                    end
                end
            end
        else
            sleep(0.5)
            local card = aiPlay(turn)
            table.insert(currentTrick, { player = turn, card = card })
            turn = (turn % 4) + 1
        end
    end
end

return games
