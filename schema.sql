-- ========================================================
-- SECTION: Products
-- Description: Core product catalog, categories, and variation
--              structures. Includes automatic SKU generation
--              for product variations based on variation items.
-- ========================================================

    -- Products table: base product information.
    CREATE TABLE products (
        id SERIAL PRIMARY KEY,
        name VARCHAR(150) NOT NULL,
        description TEXT,
        cost NUMERIC(10,2),
        price NUMERIC(10,2),
        main_sku VARCHAR(50) UNIQUE NOT NULL,
        category_id INT REFERENCES categories(id)
    );

    -- Categories table: product category metadata.
    CREATE TABLE categories (
        id SERIAL PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        description TEXT
    );

    -- Variation types define the dimension of a variation
    -- (e.g. Color, Size, Voltage).
    CREATE TABLE variation_types (
        id SERIAL PRIMARY KEY,
        name VARCHAR(50) NOT NULL
    );

    -- Variation values hold concrete values for a variation type
    -- (e.g. "Black", "White", "40", "41").
    CREATE TABLE variation_values (
        id SERIAL PRIMARY KEY,
        variation_type_id INT REFERENCES variation_types(id),
        value VARCHAR(50) NOT NULL
    );

    -- Product variations represent specific SKUs at the
    -- variation combination level (e.g. product + color + size).
    CREATE TABLE product_variations (
        id SERIAL PRIMARY KEY,
        product_id INT REFERENCES products(id),
        sku VARCHAR(100) UNIQUE,
        stock INT DEFAULT 0
    );

    -- Bridge table linking a product_variation to its selected
    -- variation_values (many-to-many relationship).
    CREATE TABLE product_variation_items (
        id SERIAL PRIMARY KEY,
        variation_id INT REFERENCES product_variations(id),
        variation_value_id INT REFERENCES variation_values(id)
    );

    -- Trigger function: regenerate the `sku` for a
    -- `product_variation` after a variation item is inserted.
    -- The SKU is constructed as: <product.main_sku>-<value1>-<value2>...
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

        -- Build suffix using variation values ordered by variation type
        SELECT string_agg(v.value, '-' ORDER BY vt.name)
        INTO suffix
        FROM product_variation_items pvi
        JOIN variation_values v ON v.id = pvi.variation_value_id
        JOIN variation_types vt ON vt.id = v.variation_type_id
        WHERE pvi.variation_id = NEW.variation_id;

        -- Persist new SKU on the product_variations row
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

    -- ========================================================
    -- SECTION: Stocking
    -- Description: Suppliers, stock locations, core stock table,
    --              and stock movement handling with automatic
    --              updates to the `stock` table.
    -- ========================================================

    -- Suppliers table: vendor contact information.
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

    -- Mapping table linking suppliers and the products they supply.
    CREATE TABLE supplier_products (
        id SERIAL PRIMARY KEY,
        supplier_id INT REFERENCES suppliers(id),
        product_id INT REFERENCES products(id),
        UNIQUE (supplier_id, product_id)
    );

    -- Physical stock locations (warehouses, stores, etc.).
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

    -- Core stock table: quantity per product_variation per location.
    CREATE TABLE stock (
        id SERIAL PRIMARY KEY,
        product_variation_id INT REFERENCES product_variations(id),
        stock_location_id INT REFERENCES stock_locations(id),
        quantity INT NOT NULL DEFAULT 0 CHECK (quantity >= 0),
        UNIQUE (product_variation_id, stock_location_id)
    );

    -- Stock movement types: additions, removals, and transfers.
    CREATE TYPE movement_type AS ENUM ('IN', 'OUT', 'TRANSFER');

    -- Records representing stock movements. Either origin or
    -- destination may be NULL depending on movement type.
    CREATE TABLE stock_movements (
        id SERIAL PRIMARY KEY,
        product_variation_id INT REFERENCES product_variations(id),
        origin_location_id INT REFERENCES stock_locations(id),
        destination_location_id INT REFERENCES stock_locations(id),
        quantity INT NOT NULL,
        movement_type movement_type NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    -- Trigger function: apply stock movements to the `stock` table.
    CREATE OR REPLACE FUNCTION update_stock_after_movement()
    RETURNS TRIGGER AS $$
    BEGIN

        -- Handle incoming stock: add to destination location.
        IF NEW.movement_type = 'IN' THEN
            INSERT INTO stock (product_variation_id, stock_location_id, quantity)
            VALUES (NEW.product_variation_id, NEW.destination_location_id, NEW.quantity)
            ON CONFLICT (product_variation_id, stock_location_id)
            DO UPDATE SET quantity = stock.quantity + NEW.quantity;
        END IF;

        -- Handle outgoing stock: subtract from origin location.
        IF NEW.movement_type = 'OUT' THEN
            UPDATE stock
            SET quantity = quantity - NEW.quantity
            WHERE product_variation_id = NEW.product_variation_id
            AND stock_location_id = NEW.origin_location_id;
        END IF;

        -- Handle transfers: subtract from origin and add to destination.
        IF NEW.movement_type = 'TRANSFER' THEN
            -- Subtract from the origin location.
            UPDATE stock
            SET quantity = quantity - NEW.quantity
            WHERE product_variation_id = NEW.product_variation_id
            AND stock_location_id = NEW.origin_location_id;

            -- Add to the destination location.
            INSERT INTO stock (product_variation_id, stock_location_id, quantity)
            VALUES (NEW.product_variation_id, NEW.destination_location_id, NEW.quantity)
            ON CONFLICT (product_variation_id, stock_location_id)
            DO UPDATE SET quantity = stock.quantity + NEW.quantity;
        END IF;

        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;

    -- Trigger to apply stock movements automatically.
    CREATE TRIGGER trg_update_stock
    AFTER INSERT ON stock_movements
    FOR EACH ROW
    EXECUTE FUNCTION update_stock_after_movement();

    -- ========================================================
    -- SECTION: Ordering
    -- Description: Customers, sellers, orders, order items,
    --              reservation of stock for orders, and
    --              order confirmation/cancellation logic.
    -- ========================================================

    -- Customers table: buyer contact information.
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

    -- Sellers: ERP users or sales representatives.
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

    -- Order lifecycle statuses.
    CREATE TYPE order_status AS ENUM ('PENDING', 'CONFIRMED', 'CANCELLED');

    -- Orders table: links customer and seller with status and timestamp.
    CREATE TABLE orders (
        id SERIAL PRIMARY KEY,
        customer_id INT REFERENCES customers(id),
        seller_id INT REFERENCES sellers(id),
        status order_status DEFAULT 'PENDING',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    -- Order items: individual SKU lines for an order.
    CREATE TABLE order_items (
        id SERIAL PRIMARY KEY,
        order_id INT REFERENCES orders(id) ON DELETE CASCADE,
        product_variation_id INT REFERENCES product_variations(id),
        quantity INT NOT NULL,
        price NUMERIC(10,2) NOT NULL
    );

    -- Stock reservations: temporary allocations of stock per order item.
    CREATE TABLE stock_reservations (
        id SERIAL PRIMARY KEY,
        product_variation_id INT REFERENCES product_variations(id),
        stock_location_id INT REFERENCES stock_locations(id),
        order_item_id INT REFERENCES order_items(id),
        quantity INT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    -- Trigger function: reserve available stock when an order item is created.
    CREATE OR REPLACE FUNCTION reserve_stock()
    RETURNS TRIGGER AS $$
    DECLARE
        remaining_qty INT;
        current_stock RECORD;
    BEGIN
        remaining_qty := NEW.quantity;

        -- Iterate through locations with available stock, preferring larger quantities.
        -- Iterate through locations calculating AVAILABLE stock (physical - reserved)
        FOR current_stock IN
            SELECT
                s.stock_location_id,
                s.quantity,
                (s.quantity - COALESCE((
                    SELECT SUM(sr.quantity)
                    FROM stock_reservations sr
                    JOIN order_items oi ON oi.id = sr.order_item_id
                    JOIN orders o ON o.id = oi.order_id
                    WHERE sr.stock_location_id = s.stock_location_id
                      AND sr.product_variation_id = s.product_variation_id
                      AND o.status = 'PENDING'
                ), 0)) AS available_quantity
            FROM stock s
            WHERE s.product_variation_id = NEW.product_variation_id
            ORDER BY available_quantity DESC
        LOOP
            -- Skip if no available stock at this location
            CONTINUE WHEN current_stock.available_quantity <= 0;
            EXIT WHEN remaining_qty <= 0;

            -- Reserve up to the available_quantity (not physical quantity)
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
                LEAST(current_stock.available_quantity, remaining_qty)
            );

            remaining_qty := remaining_qty - LEAST(current_stock.available_quantity, remaining_qty);
        END LOOP;

        IF remaining_qty > 0 THEN
            RAISE EXCEPTION 'Not enough stock to fulfill order item';
        END IF;

        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;

    -- Trigger to reserve stock for each inserted order item.
    CREATE TRIGGER trg_reserve_stock
    AFTER INSERT ON order_items
    FOR EACH ROW
    EXECUTE FUNCTION reserve_stock();

    -- Trigger function: when an order is confirmed, deduct reserved stock
    -- from the corresponding locations.
    CREATE OR REPLACE FUNCTION confirm_order()
    RETURNS TRIGGER AS $$
    DECLARE
        res RECORD;
    BEGIN
        -- Only act when status transitions to CONFIRMED.
        IF NEW.status = 'CONFIRMED' THEN

            FOR res IN
                SELECT sr.*
                FROM stock_reservations sr
                JOIN order_items oi ON oi.id = sr.order_item_id
                WHERE oi.order_id = NEW.id
            LOOP
                -- Subtract reserved quantity from stock.
                UPDATE stock
                SET quantity = quantity - res.quantity
                WHERE product_variation_id = res.product_variation_id
                AND stock_location_id = res.stock_location_id;
            END LOOP;

        END IF;

        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;

    -- Trigger to process stock deduction when order status updates.
    CREATE TRIGGER trg_confirm_order
    AFTER UPDATE ON orders
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION confirm_order();

    -- Trigger function: when order is cancelled, release any reservations.
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

    -- Trigger to release reservations on order cancellation.
    CREATE TRIGGER trg_cancel_order
    AFTER UPDATE ON orders
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION cancel_order();
    -- END OF THE ORDERING LOGIC --

    -- ========================================================
    -- SECTION: Payments and Invoices
    -- Description: payment records, invoice generation and
    --              automatic order status updates on payment.
    -- ========================================================

    -- Payment methods supported by the system.
    CREATE TYPE payment_method AS ENUM (
        'CASH',
        'CREDIT_CARD',
        'DEBIT_CARD',
        'PIX',
        'BANK_TRANSFER'
    );

    -- Payment status values.
    CREATE TYPE payment_status AS ENUM (
        'PENDING',
        'PAID',
        'FAILED',
        'REFUNDED'
    );

    -- Payments table: records payments associated to orders.
    CREATE TABLE payments (
        id SERIAL PRIMARY KEY,
        order_id INT REFERENCES orders(id) ON DELETE CASCADE,
        method payment_method NOT NULL,
        status payment_status DEFAULT 'PENDING',
        amount NUMERIC(10,2) NOT NULL,
        paid_at TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    -- Invoice lifecycle statuses.
    CREATE TYPE invoice_status AS ENUM (
        'DRAFT',
        'ISSUED',
        'CANCELLED'
    );

    -- Invoices table: one invoice per order (if generated).
    CREATE TABLE invoices (
        id SERIAL PRIMARY KEY,
        order_id INT UNIQUE REFERENCES orders(id),
        number VARCHAR(50) UNIQUE, -- invoice number (NF-e, etc.)
        status invoice_status DEFAULT 'DRAFT',
        total_amount NUMERIC(10,2),
        issued_at TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    -- Invoice items: line items copied from order_items when invoice is created.
    CREATE TABLE invoice_items (
        id SERIAL PRIMARY KEY,
        invoice_id INT REFERENCES invoices(id) ON DELETE CASCADE,
        product_variation_id INT REFERENCES product_variations(id),
        quantity INT NOT NULL,
        unit_price NUMERIC(10,2) NOT NULL,
        total_price NUMERIC(10,2) NOT NULL
    );

    -- Trigger function: mark order as CONFIRMED when a payment becomes PAID.
    CREATE OR REPLACE FUNCTION update_order_after_payment()
    RETURNS TRIGGER AS $$
    BEGIN
        IF NEW.status = 'PAID' THEN
            UPDATE orders
            SET status = 'CONFIRMED'
            WHERE id = NEW.order_id;
        END IF;

        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;

    CREATE TRIGGER trg_payment_confirm_order
    AFTER UPDATE ON payments
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION update_order_after_payment();

    -- Trigger function: generate invoice and copy items when an order is CONFIRMED.
    CREATE OR REPLACE FUNCTION create_invoice_after_order()
    RETURNS TRIGGER AS $$
    DECLARE
        total NUMERIC(10,2);
        item RECORD;
        invoice_id INT;
    BEGIN
        IF NEW.status = 'CONFIRMED' THEN

            -- Calculate invoice total from the order items.
            SELECT SUM(quantity * price)
            INTO total
            FROM order_items
            WHERE order_id = NEW.id;

            -- Create invoice in DRAFT status and remember its id.
            INSERT INTO invoices (order_id, total_amount, status)
            VALUES (NEW.id, total, 'DRAFT')
            RETURNING id INTO invoice_id;

            -- Copy order items into invoice_items.
            FOR item IN
                SELECT * FROM order_items WHERE order_id = NEW.id
            LOOP
                INSERT INTO invoice_items (
                    invoice_id,
                    product_variation_id,
                    quantity,
                    unit_price,
                    total_price
                )
                VALUES (
                    invoice_id,
                    item.product_variation_id,
                    item.quantity,
                    item.price,
                    item.quantity * item.price
                );
            END LOOP;

        END IF;

        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;

    CREATE TRIGGER trg_create_invoice
    AFTER UPDATE ON orders
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION create_invoice_after_order();

    -- Trigger function: set invoice `number` and `issued_at` when status becomes ISSUED.
    CREATE OR REPLACE FUNCTION issue_invoice()
    RETURNS TRIGGER AS $$
    BEGIN
        IF NEW.status = 'ISSUED' THEN
            NEW.issued_at := CURRENT_TIMESTAMP;

            -- Simple invoice number generation: INV-<id>-<epoch_seconds>
            NEW.number := 'INV-' || NEW.id || '-' || EXTRACT(EPOCH FROM NOW());
        END IF;

        RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;

    CREATE TRIGGER trg_issue_invoice
    BEFORE UPDATE ON invoices
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION issue_invoice();
    -- END OF THE PAYMENT AND INVOICES LOGIC --
