-- START OF THE PRODUCTS LOGIC (Usage queries in the README.md) --
-- Products Base
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    cost NUMERIC(10,2),
    price NUMERIC(10,2),
    main_sku VARCHAR(50) UNIQUE NOT NULL,
    category_id INT REFERENCES categories(id)
);

-- Categories Base
CREATE TABLE categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT
);

-- Variation Types (Examples: Color, Size, Voltage)
CREATE TABLE variation_types (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL
);

-- Variation Values (Examples: Black, White, 40, 41...)
CREATE TABLE variation_values (
    id SERIAL PRIMARY KEY,
    variation_type_id INT REFERENCES variation_types(id),
    value VARCHAR(50) NOT NULL
);

-- Product Variations (Actual SKU level)
CREATE TABLE product_variations (
    id SERIAL PRIMARY KEY,
    product_id INT REFERENCES products(id),
    sku VARCHAR(100) UNIQUE,
    stock INT DEFAULT 0
);

-- Variation Items (bridge table)
CREATE TABLE product_variation_items (
    id SERIAL PRIMARY KEY,
    variation_id INT REFERENCES product_variations(id),
    variation_value_id INT REFERENCES variation_values(id)
);

-- Automatic Trigger for SKU generation
CREATE OR REPLACE FUNCTION update_variation_sku()
RETURNS TRIGGER AS $$
DECLARE
    base_sku TEXT;
    suffix TEXT;
BEGIN
    -- Get Main SKU
    SELECT p.main_sku
    INTO base_sku
    FROM products p
    JOIN product_variations pv ON pv.product_id = p.id
    WHERE pv.id = NEW.variation_id;

    -- Build Suffix (color, size, etc.)
    SELECT string_agg(v.value, '-' ORDER BY vt.name)
    INTO suffix
    FROM product_variation_items pvi
    JOIN variation_values v ON v.id = pvi.variation_value_id
    JOIN variation_types vt ON vt.id = v.variation_type_id
    WHERE pvi.variation_id = NEW.variation_id;

    -- Update SKU
    UPDATE product_variations
    SET sku = base_sku || '-' || suffix
    WHERE id = NEW.variation_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_variation_sku
AFTER INSERT ON product_variation_items
FOR EACH ROW
EXECUTE FUNCTION update_variation_sku();
-- END OF THE PRODUCTS LOGIC --

-- START OF THE STOCKING LOGIC --
-- Suppliers Base --
CREATE TABLE suppliers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    street VARCHAR(150),
    number VARCHAR(20),
    neighborhood VARCHAR(100),
    city VARCHAR(100),
    state CHAR(2)
);

-- Suppliers for Products --
CREATE TABLE supplier_products (
    id SERIAL PRIMARY KEY,
    supplier_id INT REFERENCES suppliers(id),
    product_id INT REFERENCES products(id),
    UNIQUE (supplier_id, product_id)
);

-- Stock Locations --
CREATE TABLE stock_locations (
    id SERIAL PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    manager_name VARCHAR(150),
    manager_phone VARCHAR(20),
    street VARCHAR(150),
    number VARCHAR(20),
    neighborhood VARCHAR(100),
    city VARCHAR(100),
    state CHAR(2)
);

-- CORE STOCK TABLE
CREATE TABLE stock (
    id SERIAL PRIMARY KEY,
    product_variation_id INT REFERENCES product_variations(id),
    stock_location_id INT REFERENCES stock_locations(id),
    quantity INT NOT NULL DEFAULT 0,
    
    UNIQUE (product_variation_id, stock_location_id)
);

-- Stock Movements
CREATE TYPE movement_type AS ENUM ('IN', 'OUT', 'TRANSFER');

CREATE TABLE stock_movements (
    id SERIAL PRIMARY KEY,
    product_variation_id INT REFERENCES product_variations(id),
    
    origin_location_id INT REFERENCES stock_locations(id),
    destination_location_id INT REFERENCES stock_locations(id),
    
    quantity INT NOT NULL,
    movement_type movement_type NOT NULL,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Automatic Trigger for Stock Update
CREATE OR REPLACE FUNCTION update_stock_after_movement()
RETURNS TRIGGER AS $$
BEGIN

    -- In
    IF NEW.movement_type = 'IN' THEN
        INSERT INTO stock (product_variation_id, stock_location_id, quantity)
        VALUES (NEW.product_variation_id, NEW.destination_location_id, NEW.quantity)
        ON CONFLICT (product_variation_id, stock_location_id)
        DO UPDATE SET quantity = stock.quantity + NEW.quantity;
    END IF;

    -- Out
    IF NEW.movement_type = 'OUT' THEN
        UPDATE stock
        SET quantity = quantity - NEW.quantity
        WHERE product_variation_id = NEW.product_variation_id
        AND stock_location_id = NEW.origin_location_id;
    END IF;

    -- Transfer
    IF NEW.movement_type = 'TRANSFER' THEN
        
        -- Remove from the origin
        UPDATE stock
        SET quantity = quantity - NEW.quantity
        WHERE product_variation_id = NEW.product_variation_id
        AND stock_location_id = NEW.origin_location_id;

        -- Add to the destinated
        INSERT INTO stock (product_variation_id, stock_location_id, quantity)
        VALUES (NEW.product_variation_id, NEW.destination_location_id, NEW.quantity)
        ON CONFLICT (product_variation_id, stock_location_id)
        DO UPDATE SET quantity = stock.quantity + NEW.quantity;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Stock Update Trigger
CREATE TRIGGER trg_update_stock
AFTER INSERT ON stock_movements
FOR EACH ROW
EXECUTE FUNCTION update_stock_after_movement();
-- END OF THE STOCKING LOGIC --

-- START OF THE ORDERING LOGIC --
-- CUSTOMERS
CREATE TABLE customers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    phone VARCHAR(20),
    street VARCHAR(150),
    number VARCHAR(20),
    neighborhood VARCHAR(100),
    city VARCHAR(100),
    state CHAR(2)
);

-- SELLERS (ERP USERS)
CREATE TABLE sellers (
    id SERIAL PRIMARY KEY,
    name VARCHAR(150) NOT NULL,
    phone VARCHAR(20),
    document VARCHAR(50), -- optional identification (CPF, ID, etc.)
    street VARCHAR(150),
    number VARCHAR(20),
    neighborhood VARCHAR(100),
    city VARCHAR(100),
    state CHAR(2)
);

-- ORDERS
CREATE TYPE order_status AS ENUM ('PENDING', 'CONFIRMED', 'CANCELLED');

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    customer_id INT REFERENCES customers(id),
    seller_id INT REFERENCES sellers(id),
    status order_status DEFAULT 'PENDING',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ORDER ITEMS
CREATE TABLE order_items (
    id SERIAL PRIMARY KEY,
    order_id INT REFERENCES orders(id) ON DELETE CASCADE,
    product_variation_id INT REFERENCES product_variations(id),
    quantity INT NOT NULL,
    price NUMERIC(10,2) NOT NULL
);

-- STOCK RESERVATIONS
CREATE TABLE stock_reservations (
    id SERIAL PRIMARY KEY,
    product_variation_id INT REFERENCES product_variations(id),
    stock_location_id INT REFERENCES stock_locations(id),
    order_item_id INT REFERENCES order_items(id),
    quantity INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- RESERVE STOCK WHEN ORDER ITEM IS CREATED
CREATE OR REPLACE FUNCTION reserve_stock()
RETURNS TRIGGER AS $$
DECLARE
    remaining_qty INT;
    current_stock RECORD;
BEGIN
    remaining_qty := NEW.quantity;

    -- Loop through available stock locations
    FOR current_stock IN
        SELECT *
        FROM stock
        WHERE product_variation_id = NEW.product_variation_id
        AND quantity > 0
        ORDER BY quantity DESC
    LOOP
        EXIT WHEN remaining_qty <= 0;

        -- Reserve as much as possible
        INSERT INTO stock_reservations (
            product_variation_id,
            stock_location_id,
            order_item_id,
            quantity
        )
        VALUES (
            NEW.product_variation_id,
            current_stock.stock_location_id,
            NEW.id,
            LEAST(current_stock.quantity, remaining_qty)
        );

        remaining_qty := remaining_qty - current_stock.quantity;
    END LOOP;

    IF remaining_qty > 0 THEN
        RAISE EXCEPTION 'Not enough stock to fulfill order item';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger
CREATE TRIGGER trg_reserve_stock
AFTER INSERT ON order_items
FOR EACH ROW
EXECUTE FUNCTION reserve_stock();

-- CONFIRM ORDER → REMOVE STOCK (LOWER INVENTORY)
CREATE OR REPLACE FUNCTION confirm_order()
RETURNS TRIGGER AS $$
DECLARE
    res RECORD;
BEGIN
    -- Only process when status changes to CONFIRMED
    IF NEW.status = 'CONFIRMED' THEN

        FOR res IN
            SELECT sr.*
            FROM stock_reservations sr
            JOIN order_items oi ON oi.id = sr.order_item_id
            WHERE oi.order_id = NEW.id
        LOOP

            -- remove stock
            UPDATE stock
            SET quantity = quantity - res.quantity
            WHERE product_variation_id = res.product_variation_id
            AND stock_location_id = res.stock_location_id;

        END LOOP;

    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- trigger
CREATE TRIGGER trg_confirm_order
AFTER UPDATE ON orders
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION confirm_order();

-- CANCEL ORDER → RELEASE RESERVED STOCK
CREATE OR REPLACE FUNCTION cancel_order()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'CANCELLED' THEN
        DELETE FROM stock_reservations
        WHERE order_item_id IN (
            SELECT id FROM order_items WHERE order_id = NEW.id
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger
CREATE TRIGGER trg_cancel_order
AFTER UPDATE ON orders
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION cancel_order();
-- END OF THE ORDERING LOGIC --
